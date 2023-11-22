'''
__init__.pyx

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

cdef extern from "pyfuse3.h":
    int PLATFORM
    enum:
        PLATFORM_LINUX
        PLATFORM_BSD
        PLATFORM_DARWIN

###########
# C IMPORTS
###########

from fuse_lowlevel cimport *
from .macros cimport *
from posix.stat cimport struct_stat, S_IFMT, S_IFDIR, S_IFREG
from posix.types cimport mode_t, dev_t, off_t
from libc.stdint cimport uint32_t
from libc.stdlib cimport const_char
from libc cimport stdlib, string, errno
from posix cimport unistd
from libc.errno cimport EACCES, ETIMEDOUT, EPROTO, EINVAL, ENOMSG, ENOATTR
from posix.unistd cimport getpid
from posix.time cimport timespec
from cpython.bytes cimport (PyBytes_AsStringAndSize, PyBytes_FromStringAndSize,
                            PyBytes_AsString, PyBytes_FromString, PyBytes_AS_STRING)
from cpython.buffer cimport (PyObject_GetBuffer, PyBuffer_Release,
                             PyBUF_CONTIG_RO, PyBUF_CONTIG)
cimport cpython.exc
cimport cython
cimport libc_extra


########################
# EXTERNAL DEFINITIONS #
########################


cdef extern from "<linux/fs.h>" nogil:
  enum:
    RENAME_EXCHANGE
    RENAME_NOREPLACE

cdef extern from "Python.h" nogil:
    int PY_SSIZE_T_MAX

# Actually passed as -D to cc (and defined in setup.py)
cdef extern from *:
    char* PYFUSE3_VERSION

################
# PYTHON IMPORTS
################

from pickle import PicklingError
from queue import Queue
import logging
import os
import os.path
import sys
import trio
import threading
import typing

from . import _pyfuse3
_pyfuse3.FUSEError = FUSEError

from ._pyfuse3 import (Operations, async_wrapper, FileHandleT, FileNameT,
                       FlagT, InodeT, ModeT, XAttrNameT)


##################
# GLOBAL VARIABLES
##################

log = logging.getLogger("pyfuse3")
fse = sys.getfilesystemencoding()

cdef object operations
cdef object mountpoint_b
cdef fuse_session* session = NULL
cdef fuse_lowlevel_ops fuse_ops
cdef int session_fd
cdef object py_retval

cdef object _notify_queue = None

ROOT_INODE = FUSE_ROOT_ID
__version__ = PYFUSE3_VERSION.decode('utf-8')

_NANOS_PER_SEC = 1000000000

# In the Cython source, we want the names to refer to the
# C constants. Therefore, we assign through globals().
g = globals()
g['ENOATTR'] = ENOATTR
g['RENAME_EXCHANGE'] = RENAME_EXCHANGE
g['RENAME_NOREPLACE'] = RENAME_NOREPLACE

trio_token = None


#######################
# FUSE REQUEST HANDLERS
#######################

include "handlers.pxi"


########################################
# INTERNAL FUNCTIONS & DATA STRUCTURES #
########################################

include "internal.pxi"


######################
# EXTERNAL API       #
######################

@cython.freelist(10)
cdef class RequestContext:
    '''
    Instances of this class are passed to some `Operations` methods to
    provide information about the caller of the syscall that initiated
    the request.
    '''

    cdef readonly uid_t uid
    cdef readonly pid_t pid
    cdef readonly gid_t gid
    cdef readonly mode_t umask

    def __getstate__(self):
        raise PicklingError("RequestContext instances can't be pickled")


@cython.freelist(10)
cdef class SetattrFields:
    '''
    `SetattrFields` instances are passed to the `~Operations.setattr` handler
    to specify which attributes should be updated.
    '''

    cdef readonly object update_atime
    cdef readonly object update_mtime
    cdef readonly object update_ctime
    cdef readonly object update_mode
    cdef readonly object update_uid
    cdef readonly object update_gid
    cdef readonly object update_size

    def __cinit__(self):
        self.update_atime = False
        self.update_mtime = False
        self.update_ctime = False
        self.update_mode = False
        self.update_uid = False
        self.update_gid = False
        self.update_size = False

    def __getstate__(self):
        raise PicklingError("SetattrFields instances can't be pickled")


@cython.freelist(30)
cdef class EntryAttributes:
    '''
    Instances of this class store attributes of directory entries.
    Most of the attributes correspond to the elements of the ``stat``
    C struct as returned by e.g. ``fstat`` and should be
    self-explanatory.
    '''

    # Attributes are documented in rst/data.rst

    cdef fuse_entry_param fuse_param
    cdef struct_stat *attr

    def __cinit__(self):
        string.memset(&self.fuse_param, 0, sizeof(fuse_entry_param))
        self.attr = &self.fuse_param.attr
        self.fuse_param.generation = 0
        self.fuse_param.entry_timeout = 300
        self.fuse_param.attr_timeout = 300

        self.attr.st_mode = S_IFREG
        self.attr.st_blksize = 4096
        self.attr.st_nlink = 1

    @property
    def st_ino(self):
        return self.fuse_param.ino
    @st_ino.setter
    def st_ino(self, val):
        self.fuse_param.ino = val
        self.attr.st_ino = val

    @property
    def generation(self):
        '''The inode generation number'''
        return self.fuse_param.generation
    @generation.setter
    def generation(self, val):
        self.fuse_param.generation = val

    @property
    def attr_timeout(self):
        '''Validity timeout for the attributes of the directory entry

        Floating point numbers may be used. Units are seconds.
        '''
        return self.fuse_param.attr_timeout
    @attr_timeout.setter
    def attr_timeout(self, val):
        self.fuse_param.attr_timeout = val

    @property
    def entry_timeout(self):
        '''Validity timeout for the name/existence of the directory entry

        Floating point numbers may be used. Units are seconds.
        '''
        return self.fuse_param.entry_timeout
    @entry_timeout.setter
    def entry_timeout(self, val):
        self.fuse_param.entry_timeout = val

    @property
    def st_mode(self):
        return self.attr.st_mode
    @st_mode.setter
    def st_mode(self, val):
        self.attr.st_mode = val

    @property
    def st_nlink(self):
        return self.attr.st_nlink
    @st_nlink.setter
    def st_nlink(self, val):
        self.attr.st_nlink = val

    @property
    def st_uid(self):
        return self.attr.st_uid
    @st_uid.setter
    def st_uid(self, val):
        self.attr.st_uid = val

    @property
    def st_gid(self):
        return self.attr.st_gid
    @st_gid.setter
    def st_gid(self, val):
        self.attr.st_gid = val

    @property
    def st_rdev(self):
        return self.attr.st_rdev
    @st_rdev.setter
    def st_rdev(self, val):
        self.attr.st_rdev = val

    @property
    def st_size(self):
        return self.attr.st_size
    @st_size.setter
    def st_size(self, val):
        self.attr.st_size = val

    @property
    def st_blocks(self):
        return self.attr.st_blocks
    @st_blocks.setter
    def st_blocks(self, val):
        self.attr.st_blocks = val

    @property
    def st_blksize(self):
        return self.attr.st_blksize
    @st_blksize.setter
    def st_blksize(self, val):
        self.attr.st_blksize = val

    @property
    def st_atime_ns(self):
        '''Time of last access in (integer) nanoseconds'''
        return (int(self.attr.st_atime) * _NANOS_PER_SEC + GET_ATIME_NS(self.attr))
    @st_atime_ns.setter
    def st_atime_ns(self, val):
        self.attr.st_atime = val // _NANOS_PER_SEC
        SET_ATIME_NS(self.attr, val % _NANOS_PER_SEC)

    @property
    def st_mtime_ns(self):
        '''Time of last modification in (integer) nanoseconds'''
        return (int(self.attr.st_mtime) * _NANOS_PER_SEC + GET_MTIME_NS(self.attr))
    @st_mtime_ns.setter
    def st_mtime_ns(self, val):
        self.attr.st_mtime = val // _NANOS_PER_SEC
        SET_MTIME_NS(self.attr, val % _NANOS_PER_SEC)

    @property
    def st_ctime_ns(self):
        '''Time of last inode modification in (integer) nanoseconds'''
        return (int(self.attr.st_ctime) * _NANOS_PER_SEC + GET_CTIME_NS(self.attr))
    @st_ctime_ns.setter
    def st_ctime_ns(self, val):
        self.attr.st_ctime = val // _NANOS_PER_SEC
        SET_CTIME_NS(self.attr, val % _NANOS_PER_SEC)

    @property
    def st_birthtime_ns(self):
        '''Time of inode creation in (integer) nanoseconds.

        Only available under BSD and OS X. Will be zero on Linux.
        '''

        # Use C macro to prevent compiler error on Linux
        # (where st_birthtime does not exist)
        return int(GET_BIRTHTIME(self.attr) * _NANOS_PER_SEC
                    + GET_BIRTHTIME_NS(self.attr))

    @st_birthtime_ns.setter
    def st_birthtime_ns(self, val):
        # Use C macro to prevent compiler error on Linux
        # (where st_birthtime does not exist)
        SET_BIRTHTIME(self.attr, val // _NANOS_PER_SEC)
        SET_BIRTHTIME_NS(self.attr, val % _NANOS_PER_SEC)

    # Pickling and copy support
    def __getstate__(self):
        state = dict()
        for k in ('st_ino', 'generation', 'entry_timeout', 'attr_timeout',
                  'st_mode', 'st_nlink', 'st_uid', 'st_gid', 'st_rdev',
                  'st_size', 'st_blksize', 'st_blocks', 'st_atime_ns',
                  'st_ctime_ns', 'st_mtime_ns', 'st_birthtime_ns'):
            state[k] = getattr(self, k)
        return state

    def __setstate__(self, state):
        for (k,v) in state.items():
            setattr(self, k, v)


@cython.freelist(10)
cdef class FileInfo:
    '''
    Instances of this class store options and data that `Operations.open`
    returns. The attributes correspond to the elements of the ``fuse_file_info``
    struct that are relevant to the `Operations.open` function.
    '''

    cdef public uint64_t fh
    cdef public bint direct_io
    cdef public bint keep_cache
    cdef public bint nonseekable

    def __cinit__(self, fh=0, direct_io=0, keep_cache=1, nonseekable=0):
        self.fh = fh
        self.direct_io = direct_io
        self.keep_cache = keep_cache
        self.nonseekable = nonseekable

    cdef _copy_to_fuse(self, fuse_file_info *out):
        out.fh = self.fh

        # Due to how Cython generates its C code, GCC will complain about
        # assigning to the bitfields in the fuse_file_info struct.
        # This is the workaround.
        if self.direct_io:
            out.direct_io = 1
        else:
            out.direct_io = 0

        if self.keep_cache:
            out.keep_cache = 1
        else:
            out.keep_cache = 0

        if self.nonseekable:
            out.nonseekable = 1
        else:
            out.nonseekable = 0


@cython.freelist(1)
cdef class StatvfsData:
    '''
    Instances of this class store information about the file system.
    The attributes correspond to the elements of the ``statvfs``
    struct, see :manpage:`statvfs(2)` for details.
    '''

    cdef statvfs stat

    def __cinit__(self):
        string.memset(&self.stat, 0, sizeof(statvfs))

    @property
    def f_bsize(self):
        return self.stat.f_bsize
    @f_bsize.setter
    def f_bsize(self, val):
        self.stat.f_bsize = val

    @property
    def f_frsize(self):
        return self.stat.f_frsize
    @f_frsize.setter
    def f_frsize(self, val):
        self.stat.f_frsize = val

    @property
    def f_blocks(self):
        return self.stat.f_blocks
    @f_blocks.setter
    def f_blocks(self, val):
        self.stat.f_blocks = val

    @property
    def f_bfree(self):
        return self.stat.f_bfree
    @f_bfree.setter
    def f_bfree(self, val):
        self.stat.f_bfree = val

    @property
    def f_bavail(self):
        return self.stat.f_bavail
    @f_bavail.setter
    def f_bavail(self, val):
        self.stat.f_bavail = val

    @property
    def f_files(self):
        return self.stat.f_files
    @f_files.setter
    def f_files(self, val):
        self.stat.f_files = val

    @property
    def f_ffree(self):
        return self.stat.f_ffree
    @f_ffree.setter
    def f_ffree(self, val):
        self.stat.f_ffree = val

    @property
    def f_favail(self):
        return self.stat.f_favail
    @f_favail.setter
    def f_favail(self, val):
        self.stat.f_favail = val

    @property
    def f_namemax(self):
        return self.stat.f_namemax
    @f_namemax.setter
    def f_namemax(self, val):
        self.stat.f_namemax = val

    # Pickling and copy support
    def __getstate__(self):
        state = dict()
        for k in ('f_bsize', 'f_frsize', 'f_blocks', 'f_bfree',
                  'f_bavail', 'f_files', 'f_ffree', 'f_favail',
                  'f_namemax'):
            state[k] = getattr(self, k)
        return state

    def __setstate__(self, state):
        for (k,v) in state.items():
            setattr(self, k, v)


# As of Cython 0.28.1, @cython.freelist cannot be used for
# classes that derive from a builtin type.
cdef class FUSEError(Exception):
    '''
    This exception may be raised by request handlers to indicate that
    the requested operation could not be carried out. The system call
    that resulted in the request (if any) will then fail with error
    code *errno_*.
    '''

    # If we call this variable "errno", we will get syntax errors
    # during C compilation (maybe something else declares errno as
    # a macro?)
    cdef readonly int errno_

    @property
    def errno(self):
        '''Error code to return to client process'''
        return self.errno_

    def __cinit__(self, errno):
        self.errno_ = errno

    def __str__(self):
        return strerror(self.errno_)


def listdir(path):
    '''Like `os.listdir`, but releases the GIL.

    This function returns an iterator over the directory entries in *path*.

    The returned values are of type :ref:`str <python:textseq>`. Surrogate
    escape coding (cf.  `PEP 383 <http://www.python.org/dev/peps/pep-0383/>`_)
    is used for directory names that do not have a string representation.
    '''

    if not isinstance(path, str):
        raise TypeError('*path* argument must be of type str')

    cdef libc_extra.DIR* dirp
    cdef libc_extra.dirent* res
    cdef char* buf

    path_b = str2bytes(path)
    buf = <char*> path_b

    with nogil:
        dirp = libc_extra.opendir(buf)

    if dirp == NULL:
        raise OSError(errno.errno, strerror(errno.errno), path)

    names = list()
    while True:
        errno.errno = 0
        with nogil:
            res = libc_extra.readdir(dirp)

        if res is NULL:
           if errno.errno != 0:
               raise OSError(errno.errno, strerror(errno.errno), path)
           else:
               break
        if string.strcmp(res.d_name, b'.') == 0 or \
           string.strcmp(res.d_name, b'..') == 0:
            continue

        names.append(bytes2str(PyBytes_FromString(res.d_name)))

    with nogil:
        libc_extra.closedir(dirp)

    return names


def syncfs(path):
    '''Sync filesystem mounted at *path*

    This is a Python interface to the syncfs(2) system call. There is no
    particular relation to libfuse, it is provided by pyfuse3 as a convience.
    '''

    cdef int ret

    fd = os.open(path, flags=os.O_DIRECTORY)
    try:
        ret = libc_extra.syncfs(fd)

        if ret != 0:
            raise OSError(errno.errno, strerror(errno.errno), path)
    finally:
        os.close(fd)


def setxattr(path, name, bytes value, namespace='user'):
    '''Set extended attribute

    *path* and *name* have to be of type `str`. In Python 3.x, they may
    contain surrogates. *value* has to be of type `bytes`.

    Under FreeBSD, the *namespace* parameter may be set to *system* or *user* to
    select the namespace for the extended attribute. For other platforms, this
    parameter is ignored.

    In contrast to the `os.setxattr` function from the standard library, the
    method provided by pyfuse3 is also available for non-Linux systems.
    '''

    if not isinstance(path, str):
        raise TypeError('*path* argument must be of type str')

    if not isinstance(name, str):
        raise TypeError('*name* argument must be of type str')

    if namespace not in ('system', 'user'):
        raise ValueError('*namespace* parameter must be "system" or "user", not %s'
                         % namespace)

    cdef int ret
    cdef Py_ssize_t len_
    cdef char *cvalue
    cdef char *cpath
    cdef char *cname
    cdef int cnamespace

    if namespace == 'system':
        cnamespace = libc_extra.EXTATTR_NAMESPACE_SYSTEM
    else:
        cnamespace = libc_extra.EXTATTR_NAMESPACE_USER

    path_b = str2bytes(path)
    name_b = str2bytes(name)
    PyBytes_AsStringAndSize(value, &cvalue, &len_)
    cpath = <char*> path_b
    cname = <char*> name_b

    with nogil:
        # len_ is guaranteed positive
        ret = libc_extra.setxattr_p(
            cpath, cname, cvalue, <size_t> len_, cnamespace)

    if ret != 0:
        raise OSError(errno.errno, strerror(errno.errno), path)


def getxattr(path, name, size_t size_guess=128, namespace='user'):
    '''Get extended attribute

    *path* and *name* have to be of type `str`. In Python 3.x, they may
    contain surrogates. Returns a value of type `bytes`.

    If the caller knows the approximate size of the attribute value,
    it should be supplied in *size_guess*. If the guess turns out
    to be wrong, the system call has to be carried out three times
    (the first call will fail, the second determines the size and
    the third finally gets the value).

    Under FreeBSD, the *namespace* parameter may be set to *system* or *user* to
    select the namespace for the extended attribute. For other platforms, this
    parameter is ignored.

    In contrast to the `os.getxattr` function from the standard library, the
    method provided by pyfuse3 is also available for non-Linux systems.
    '''

    if not isinstance(path, str):
        raise TypeError('*path* argument must be of type str')

    if not isinstance(name, str):
        raise TypeError('*name* argument must be of type str')

    if namespace not in ('system', 'user'):
        raise ValueError('*namespace* parameter must be "system" or "user", not %s'
                         % namespace)

    cdef ssize_t ret
    cdef char *buf
    cdef char *cpath
    cdef char *cname
    cdef size_t bufsize
    cdef int cnamespace

    if namespace == 'system':
        cnamespace = libc_extra.EXTATTR_NAMESPACE_SYSTEM
    else:
        cnamespace = libc_extra.EXTATTR_NAMESPACE_USER

    path_b = str2bytes(path)
    name_b = str2bytes(name)
    cpath = <char*> path_b
    cname = <char*> name_b

    bufsize = size_guess
    buf = <char*> stdlib.malloc(bufsize * sizeof(char))

    if buf is NULL:
        cpython.exc.PyErr_NoMemory()

    try:
        with nogil:
            ret = libc_extra.getxattr_p(cpath, cname, buf, bufsize, cnamespace)

        if ret < 0 and errno.errno == errno.ERANGE:
            with nogil:
                ret = libc_extra.getxattr_p(cpath, cname, NULL, 0, cnamespace)
            if ret < 0:
                raise OSError(errno.errno, strerror(errno.errno), path)
            bufsize = <size_t> ret
            stdlib.free(buf)
            buf = <char*> stdlib.malloc(bufsize * sizeof(char))
            if buf is NULL:
                cpython.exc.PyErr_NoMemory()

            with nogil:
                ret = libc_extra.getxattr_p(cpath, cname, buf, bufsize, cnamespace)

        if ret < 0:
            raise OSError(errno.errno, strerror(errno.errno), path)

        return PyBytes_FromStringAndSize(buf, ret)

    finally:
        stdlib.free(buf)


default_options = frozenset(('default_permissions',))

def init(ops, mountpoint, options=default_options):
    '''Initialize and mount FUSE file system

    *ops* has to be an instance of the `Operations` class (or another
    class defining the same methods).

    *args* has to be a set of strings. `default_options` provides some
    reasonable defaults. It is recommended to use these options as a basis and
    add or remove options as necessary. For example::

        my_opts = set(pyfuse3.default_options)
        my_opts.add('allow_other')
        my_opts.discard('default_permissions')
        pyfuse3.init(ops, mountpoint, my_opts)

    Valid options are listed under ``struct
    fuse_opt fuse_mount_opts[]``
    (in `mount.c <https://github.com/libfuse/libfuse/blob/fuse-3.2.6/lib/mount.c#L80>`_)
    and ``struct fuse_opt fuse_ll_opts[]``
    (in `fuse_lowlevel_c <https://github.com/libfuse/libfuse/blob/fuse-3.2.6/lib/fuse_lowlevel.c#L2572>`_).
    '''

    log.debug('Initializing pyfuse3')
    cdef fuse_args f_args
    cdef int res

    if not isinstance(mountpoint, str):
        raise TypeError('*mountpoint_* argument must be of type str')

    global operations
    global fuse_ops
    global mountpoint_b
    global session
    global session_fd
    global worker_data

    worker_data = _WorkerData()
    mountpoint_b = str2bytes(os.path.abspath(mountpoint))
    operations = ops

    make_fuse_args(options, &f_args)

    log.debug('Calling fuse_session_new')
    init_fuse_ops()
    session = fuse_session_new(&f_args, &fuse_ops, sizeof(fuse_ops), NULL)
    if not session:
        raise RuntimeError("fuse_session_new() failed")

    log.debug('Calling fuse_session_mount')
    res = fuse_session_mount(session, <char*>mountpoint_b)
    if res != 0:
        raise RuntimeError('fuse_session_mount failed')

    session_fd = fuse_session_fd(session)


@async_wrapper
async def main(int min_tasks=1, int max_tasks=99):
    '''Run FUSE main loop'''

    if session == NULL:
        raise RuntimeError('Need to call init() before main()')

    global trio_token
    trio_token = trio.lowlevel.current_trio_token()

    try:
        async with trio.open_nursery() as nursery:
            worker_data.task_count = 1
            worker_data.task_serial = 1
            nursery.start_soon(_session_loop, nursery, min_tasks, max_tasks,
                               name=worker_data.get_name())
    finally:
        trio_token = None
        if _notify_queue is not None:
            _notify_queue.put(None)


def terminate():
    '''Terminate FUSE main loop.

    This function gracefully terminates the FUSE main loop (resulting in the call to
    main() to return).

    When called by a thread different from the one that runs the main loop, the call must
    be wrapped with `trio.from_thread.run_sync`. The necessary *trio_token* argument can
    (for convience) be retrieved from the `trio_token` module attribute.
    '''

    fuse_session_exit(session)
    trio.lowlevel.notify_closing(session_fd)


def close(unmount=True):
    '''Clean up and ensure filesystem is unmounted

    If *unmount* is False, only clean up operations are peformed, but the file
    system is not explicitly unmounted.

    Normally, the filesystem is unmounted by the user calling umount(8) or
    fusermount(1), which then terminates the FUSE main loop. However, the loop
    may also terminate as a result of an exception or a signal. In this case the
    filesystem remains mounted, but any attempt to access it will block (while
    the filesystem process is still running) or (after the filesystem process
    has terminated) return an error. If *unmount* is True, this function will
    ensure that the filesystem is properly unmounted.

    Note: if the connection to the kernel is terminated via the
    ``/sys/fs/fuse/connections/`` interface, this function will *not* unmount
    the filesystem even if *unmount* is True.
    '''

    global mountpoint_b
    global session

    if unmount:
        log.debug('Calling fuse_session_unmount')
        fuse_session_unmount(session)

    log.debug('Calling fuse_session_destroy')
    fuse_session_destroy(session)

    mountpoint_b = None
    session = NULL


def invalidate_inode(fuse_ino_t inode, attr_only=False):
    '''Invalidate cache for *inode*

    Instructs the FUSE kernel module to forget cached attributes and
    data (unless *attr_only* is True) for *inode*.

    **This operation may block** if writeback caching is active and there is
    dirty data for the inode that is to be invalidated. Unfortunately there is
    no way to return control to the event loop until writeback is complete
    (leading to a deadlock if the necessary write() requests cannot be processed
    by the filesystem). Unless writeback caching is disabled, this function
    should therefore be called from a separate thread.

    If the operation is not supported by the kernel, raises `OSError`
    with errno ENOSYS.
    '''

    cdef int ret
    if attr_only:
        with nogil:
            ret = fuse_lowlevel_notify_inval_inode(session, inode, -1, 0)
    else:
        with nogil:
            ret = fuse_lowlevel_notify_inval_inode(session, inode, 0, 0)

    if ret != 0:
        raise OSError(-ret, 'fuse_lowlevel_notify_inval_inode returned: ' + strerror(-ret))


def invalidate_entry(fuse_ino_t inode_p, bytes name, fuse_ino_t deleted=0):
    '''Invalidate directory entry

    Instructs the FUSE kernel module to forget about the directory entry *name*
    in the directory with inode *inode_p*.

    If the inode passed as *deleted* matches the inode that is currently
    associated with *name* by the kernel, any inotify watchers of this inode are
    informed that the entry has been deleted.

    If there is a pending filesystem operation that is related to the parent
    directory or directory entry, this function will block until that operation
    has completed. Therefore, to avoid a deadlock this function must not be
    called while handling a related request, nor while holding a lock that could
    be needed for handling such a request.

    As for kernel 4.18, a "related operation" is a `~Operations.lookup`,
    `~Operations.symlink`, `~Operations.mknod`, `~Operations.mkdir`,
    `~Operations.unlink`, `~Operations.rename`, `~Operations.link` or
    `~Operations.create` request for the parent, and a `~Operations.setattr`,
    `~Operations.unlink`, `~Operations.rmdir`, `~Operations.rename`,
    `~Operations.setxattr`, `~Operations.removexattr` or `~Operations.readdir`
    request for the inode itself.

    For technical reasons, this function can also not return control to the main
    event loop but will actually block. To return control to the event loop
    while this function is running, call it in a separate thread using
    `trio.run_sync_in_worker_thread
    <https://trio.readthedocs.io/en/latest/reference-core.html#trio.run_sync_in_worker_thread>`_.
    A less complicated alternative is to use the `invalidate_entry_async` function
    instead.
    '''

    cdef char *cname
    cdef ssize_t slen
    cdef size_t len_
    cdef int ret

    PyBytes_AsStringAndSize(name, &cname, &slen)
    # len_ is guaranteed positive
    len_ = <size_t> slen

    if deleted:
        with nogil: # might block!
            ret = fuse_lowlevel_notify_delete(session, inode_p, deleted, cname, len_)
        if ret != 0:
            raise OSError(-ret, 'fuse_lowlevel_notify_delete returned: '
                          + strerror(-ret))
    else:
        with nogil: # might block!
            ret = fuse_lowlevel_notify_inval_entry(session, inode_p, cname, len_)
        if ret != 0:
            raise OSError(-ret, 'fuse_lowlevel_notify_inval_entry returned: '
                          + strerror(-ret))


def invalidate_entry_async(inode_p, name, deleted=0, ignore_enoent=False):
    '''Asynchronously invalidate directory entry

    This function performs the same operation as `invalidate_entry`, but does so
    asynchronously in a separate thread. This avoids the deadlocks that may
    occur when using `invalidate_entry` from within a request handler, but means
    that the function generally returns before the kernel has actually
    invalidated the entry, and that no errors can be reported (they will be
    logged though).

    The directory entries that are to be invalidated are put in an unbounded
    queue which is processed by a single thread. This means that if the entry at
    the beginning of the queue cannot be invalidated yet because a related file
    system operation is still in progress, none of the other entries will be
    processed and repeated calls to this function will result in continued
    growth of the queue.

    If there are errors, an exception is logged using the `logging` module.

    If *ignore_enoent* is True, ignore ENOENT errors (which occur if the
    kernel doesn't actually have knowledge of the entry that is to be
    removed).
    '''

    global _notify_queue

    if _notify_queue is None:
        log.debug('Starting notify worker.')
        _notify_queue = Queue()
        t = threading.Thread(target=_notify_loop)
        t.daemon = True
        t.start()

    _notify_queue.put((inode_p, name, deleted, ignore_enoent))


def notify_store(inode, offset, data):
    '''Store data in kernel page cache

    Sends *data* for the kernel to store it in the page cache for *inode* at
    *offset*. If this provides data beyond the current file size, the file is
    automatically extended.

    If this function raises an exception, the store may still have completed
    partially.

    If the operation is not supported by the kernel, raises `OSError`
    with errno ENOSYS.
    '''

    # This should not block, but the kernel may need to do some work so release
    # the GIL to give other threads a chance to run.

    cdef int ret
    cdef fuse_ino_t ino
    cdef off_t off
    cdef Py_buffer pybuf
    cdef fuse_bufvec bufvec
    cdef fuse_buf *buf

    PyObject_GetBuffer(data, &pybuf, PyBUF_CONTIG_RO)
    bufvec.count = 1
    bufvec.idx = 0
    bufvec.off = 0

    buf = bufvec.buf
    buf[0].flags = 0
    buf[0].mem = pybuf.buf
    buf[0].size = <size_t> pybuf.len # guaranteed positive

    ino = inode
    off = offset
    with nogil:
        ret = fuse_lowlevel_notify_store(session, ino, off, &bufvec, 0)

    PyBuffer_Release(&pybuf)
    if ret != 0:
        raise OSError(-ret, 'fuse_lowlevel_notify_store returned: ' + strerror(-ret))


def get_sup_groups(pid):
    '''Return supplementary group ids of *pid*

    This function is relatively expensive because it has to read the group ids
    from ``/proc/[pid]/status``. For the same reason, it will also not work on
    systems that do not provide a ``/proc`` file system.

    Returns a set.
    '''

    with open('/proc/%d/status' % pid, 'r') as fh:
        for line in fh:
            if line.startswith('Groups:'):
                break
        else:
            raise RuntimeError("Unable to parse %s" % fh.name)
    gids = set()
    for x in line.split()[1:]:
        gids.add(int(x))

    return gids


def readdir_reply(ReaddirToken token, name, EntryAttributes attr, off_t next_id):
    '''Report a directory entry in response to a `~Operations.readdir` request.

    This function should be called by the `~Operations.readdir` handler to
    provide the list of directory entries. The function should be called
    once for each directory entry, until it returns False.

    *token* must be the token received by the `~Operations.readdir` handler.

    *name* and must be the name of the directory entry and *attr* an
     `EntryAttributes` instance holding its attributes.

    *next_id* must be a 64-bit integer value that uniquely identifies the
    current position in the list of directory entries. It may be passed back
    to a later `~Operations.readdir` call to start another listing at the
    right position. This value should be robust in the presence of file
    removals and creations, i.e. if files are created or removed after a
    call to `~Operations.readdir` and `~Operations.readdir` is called again
    with *start_id* set to any previously supplied *next_id* values, under
    no circumstances must any file be reported twice or skipped over.
    '''

    cdef char *cname

    if token.buf_start == NULL:
        token.buf_start = <char*> calloc_or_raise(token.size, sizeof(char))
        token.buf = token.buf_start

    cname = PyBytes_AsString(name)
    len_ = fuse_add_direntry_plus(token.req, token.buf, token.size,
                                  cname, &attr.fuse_param, next_id)
    if len_ > token.size:
        return False

    token.size -= len_
    token.buf = &token.buf[len_]
    return True
