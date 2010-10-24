'''
llfuse.pyx

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of LLFUSE (http://python-llfuse.googlecode.com).
LLFUSE can be distributed under the terms of the GNU LGPL.
'''


# Version is defined in setup.py
cdef extern from *:
    char* LLFUSE_VERSION
__version__ = LLFUSE_VERSION


###########
# C IMPORTS
###########

from fuse_lowlevel cimport (fuse_args as fuse_args_t, fuse_lowlevel_new,
                            fuse_session, fuse_chan, fuse_session_add_chan,
                            fuse_mount, fuse_unmount, fuse_lowlevel_ops,
                            fuse_remove_signal_handlers, fuse_conn_info,
                            fuse_set_signal_handlers, fuse_req_t, ulong_t,
                            fuse_session_destroy, fuse_ino_t, fuse_file_info,
                            fuse_session_loop, fuse_session_loop_mt,
                            fuse_session_remove_chan, fuse_reply_err,
                            fuse_reply_entry, fuse_entry_param)
from libc.sys.stat cimport stat as c_stat, S_IFMT, S_IFDIR
from libc.sys.types cimport mode_t, dev_t, off_t
from libc.stdlib cimport const_char
from libc cimport stdlib, string, errno, dirent, xattr
from cpython.bytes cimport (PyBytes_AsStringAndSize, PyBytes_FromStringAndSize,
                            PyBytes_AsString, PyBytes_FromString)
cimport cpython.exc

######################
# EXTERNAL DEFINITIONS
######################

cdef extern from "sched.h":
    int sched_yield() nogil

# Include components written in plain C
cdef extern from "lock.c" nogil:
    int acquire() nogil
    int release() nogil
    int EINVAL
    int EDEADLK
    int EPERM

cdef extern from "time.c" nogil:
    int GET_ATIME_NS(c_stat* buf)
    int GET_CTIME_NS(c_stat* buf)
    int GET_MTIME_NS(c_stat* buf)
    
    void SET_ATIME_NS(c_stat* buf, int val)
    void SET_CTIME_NS(c_stat* buf, int val)
    void SET_MTIME_NS(c_stat* buf, int val)


################
# PYTHON IMPORTS
################

import errno
import os
import logging

    
#######################
# FUSE REQUEST HANDLERS
#######################
    
cdef void fuse_init (void *userdata, fuse_conn_info *conn) with gil:
    try:
        with lock:
            operations.init()
    except Exception as e:
        handle_exc('init', e, NULL)
        
cdef void fuse_destroy (void *userdata) with gil:
    # Note: called by fuse_session_destroy()
    try:
        with lock:
            operations.destroy()
    except Exception as e:
        handle_exc('destroy', e, NULL)


    
cdef void fuse_lookup (fuse_req_t req, fuse_ino_t parent,
                       const_char *name) with gil:
    cdef fuse_entry_param entry
    cdef int ret

    try:
        with lock:
            attr = operations.lookup(parent, PyBytes_FromString(name))

        fill_entry_param(attr, &entry)
        
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except Exception as e:
        ret = handle_exc('lookup', e, req)
    else:
        ret = fuse_reply_entry(req, &entry)

    if ret != 0:
        log.error('fuse_lookup(): fuse_reply_* failed with %s',
                  errno.errorcode.get(e.errno, str(e.errno)))
    

cdef void fuse_forget (fuse_req_t req, fuse_ino_t ino,
                       ulong_t nlookup) with gil:
    cdef int ret

    try:
        with lock:
            operations.forget(ino, nlookup)

    except Exception as e:
        handle_exc('forget', e, NULL)

    ret = fuse_reply_none(req)
    if ret != 0:
        log.error('fuse_forget(): fuse_reply_none failed with %s',
                  errno.errorcode.get(e.errno, str(e.errno)))

cdef void fuse_getattr (fuse_req_t req, fuse_ino_t ino,
                        fuse_file_info *fi) with gil:
    cdef c_stat stat
    cdef int ret
    cdef int timeout

    try:
        with lock:
            attr = operations.getattr(ino)

        fill_c_stat(attr, &stat)
        timeout = attr.attr_timeout
        
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except Exception as e:
        ret = handle_exc('getattr', e, req)
    else:
        ret = fuse_reply_attr(req, &stat, timeout)

    if ret != 0:
        log.error('fuse_getattr(): fuse_reply_* failed with %s',
                  errno.errorcode.get(e.errno, str(e.errno)))

cdef void fuse_setattr (fuse_req_t req, fuse_ino_t ino, c_stat *attr,
                        int to_set, fuse_file_info *fi) with gil:
    cdef c_stat stat
    cdef int ret
    cdef int timeout

    try:
        attr = EntryAttributes()
        
        if to_set & FUSE_SET_ATTR_ATIME:
            attr.st_atime = stat.st_atime + GET_ATIME_NS(stat) * 1e-9

        if to_set & FUSE_SET_ATTR_MTIME:
            attr.st_mtime = stat.st_mtime + GET_MTIME_NS(stat) * 1e-9

        if to_set & FUSE_SET_ATTR_MODE:
            attr.st_mode = stat.st_mode
            
        if to_set & FUSE_SET_ATTR_UID:
            attr.st_uid = stat.st_uid

        if to_set & FUSE_SET_ATTR_GID:
            attr.st_gid = stat.st_gid
            
        if to_set & FUSE_SET_ATTR_SIZE:
            attr.st_size = stat.st_size
            
        with lock:
            attr = operations.setattr(ino, attr)

        fill_c_stat(attr, &stat)
        timeout = attr.attr_timeout
        
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except Exception as e:
        ret = handle_exc('setattr', e, req)
    else:
        ret = fuse_reply_attr(req, &stat, timeout)

    if ret != 0:
        log.error('fuse_setattr(): fuse_reply_* failed with %s',
                  errno.errorcode.get(e.errno, str(e.errno)))

cdef void fuse_readlink (fuse_req_t req, fuse_ino_t ino) with gil:
    cdef int ret
    cdef char* name
    try:
        with lock:
            target = operations.readlink(ino)

        name = PyBytes_AsString(target)
            
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except Exception as e:
        ret = handle_exc('readlink', e, req)
    else:
        ret = fuse_reply_readlink(req, name)

    if ret != 0:
        log.error('fuse_readlink(): fuse_reply_* failed with %s',
                  errno.errorcode.get(e.errno, str(e.errno)))

cdef void fuse_mknod (fuse_req_t req, fuse_ino_t parent, const_char *name,
                      mode_t mode, dev_t rdev) with gil:
    cdef int ret
    cdef fuse_entry_param entry
    cdef fuse_ctx* context
    
    try:
        context = fuse_req_ctx(req)

        ctx = RequestContext()
        ctx.pid = context.pid
        ctx.uid = context.uid
        ctx.gid = context.gid
        ctx.umask = context.umask
        
        with lock:
            attr = operations.mknod(parent, PyBytes_FromString(name), mode,
                                    rdev, ctx)

        fill_entry_param(attr, &entry)
            
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except Exception as e:
        ret = handle_exc('mknod', e, req)
    else:
        ret = fuse_reply_entry(req, &entry)

    if ret != 0:
        log.error('fuse_mknod(): fuse_reply_* failed with %s',
                  errno.errorcode.get(e.errno, str(e.errno)))

cdef void fuse_mkdir (fuse_req_t req, fuse_ino_t parent, const_char *name,
                      mode_t mode) with gil:
    cdef int ret
    cdef fuse_entry_param entry
    cdef fuse_ctx* context
    
    try:
        # Force the entry type to directory
        mode = (mode & ~S_IFMT) | S_IFDIR
        
        context = fuse_req_ctx(req)
        ctx = RequestContext()
        ctx.pid = context.pid
        ctx.uid = context.uid
        ctx.gid = context.gid
        ctx.umask = context.umask
        
        with lock:
            attr = operations.mkdir(parent, PyBytes_FromString(name), mode, ctx)

        fill_entry_param(attr, &entry)
            
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except Exception as e:
        ret = handle_exc('mkdir', e, req)
    else:
        ret = fuse_reply_entry(req, &entry)

    if ret != 0:
        log.error('fuse_mkdir(): fuse_reply_* failed with %s',
                  errno.errorcode.get(e.errno, str(e.errno)))

cdef void fuse_unlink (fuse_req_t req, fuse_ino_t parent, const_char *name) with gil:
    pass

cdef void fuse_rmdir (fuse_req_t req, fuse_ino_t parent, const_char *name) with gil:
    pass

cdef void fuse_symlink (fuse_req_t req, const_char *link, fuse_ino_t parent,
                        const_char *name) with gil:
    pass

cdef void fuse_rename (fuse_req_t req, fuse_ino_t parent, const_char *name,
                       fuse_ino_t newparent, const_char *newname) with gil:
    pass

cdef void fuse_link (fuse_req_t req, fuse_ino_t ino, fuse_ino_t newparent,
                     const_char *newname) with gil:
    pass

cdef void fuse_open (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    pass

cdef void fuse_read (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                     fuse_file_info *fi) with gil:
    pass

cdef void fuse_write (fuse_req_t req, fuse_ino_t ino, const_char *buf,
                      size_t size, off_t off, fuse_file_info *fi) with gil:
    pass

cdef void fuse_flush (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    pass

cdef void fuse_release (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    pass

cdef void fuse_fsync (fuse_req_t req, fuse_ino_t ino, int datasync,
                      fuse_file_info *fi) with gil:
    pass

cdef void fuse_opendir (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    pass

cdef void fuse_readdir (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                        fuse_file_info *fi) with gil:
    pass

cdef void fuse_releasedir (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    pass

cdef void fuse_fsyncdir (fuse_req_t req, fuse_ino_t ino, int datasync,
                         fuse_file_info *fi) with gil:
    pass

cdef void fuse_statfs (fuse_req_t req, fuse_ino_t ino) with gil:
    pass

cdef void fuse_setxattr (fuse_req_t req, fuse_ino_t ino, const_char *name,
                         const_char *value, size_t size, int flags) with gil:
    pass

cdef void fuse_getxattr (fuse_req_t req, fuse_ino_t ino, const_char *name, size_t size) with gil:
    pass

cdef void fuse_listxattr (fuse_req_t req, fuse_ino_t ino, size_t size) with gil:
    pass

cdef void fuse_removexattr (fuse_req_t req, fuse_ino_t ino, const_char *name) with gil:
    pass

cdef void fuse_access (fuse_req_t req, fuse_ino_t ino, int mask) with gil:
    pass

cdef void fuse_create (fuse_req_t req, fuse_ino_t parent, const_char *name,
                       mode_t mode, fuse_file_info *fi) with gil:
    pass


####################
# FUSE API FUNCTIONS
####################

def listdir(path):
    '''Like os.listdir(), but releases the GIL'''
    
    cdef dirent.DIR* dirp
    cdef dirent.dirent ent
    cdef dirent.dirent* res
    cdef int ret

    with nogil:
        dirp = dirent.opendir(path)
    names = list()

    while True:
        errno.errno = 0
        with nogil:
            ret = dirent.readdir_r(dirp, &ent, &res)
        if ret != 0:
            raise OSError(errno, os.strerror(errno), path)
        if res is NULL:
            break
        if string.strcmp(ent.d_name, b'.') == 0 or string.strcmp(ent.d_name, b'..') == 0:
            continue

        names.append(ent.d_name)
        
    with nogil:
        dirent.closedir(dirp)
    
    return names


def setxattr(path, name, value):
    '''Set extended attribute'''

    cdef int ret
    cdef Py_ssize_t n
    cdef char* s

    ret = PyBytes_AsStringAndSize(value, &s, &n)

    with nogil:
        ret = xattr.setxattr(path, name, s, n, 0)

    if ret != 0:
        raise OSError(errno, os.strerror(errno), path)


def getxattr(path, name, int size_guess=128):
    '''Get extended attribute
    
    If the caller knows the approximate size of the attribute value,
    it should be supplied in `size_guess`. If the guess turns out
    to be wrong, the system call has to be carried out three times
    (the first call will fail, the second determines the size and
    the third finally gets the value).
    '''

    cdef int ret
    cdef char* buf
    cdef int bufsize

    bufsize = size_guess
    buf = <char*> stdlib.malloc(bufsize)

    if buf is NULL:
        cpython.exc.PyErr_NoMemory()

    try:
        with nogil:
            ret = xattr.getxattr(path, name, &buf, bufsize)

        if ret < 0 and errno.errno == errno.ERANGE:
            with nogil:
                ret = xattr.getxattr(path, name, NULL, 0)
            if ret < 0:
                raise OSError(errno, os.strerror(errno), path)
            bufsize = ret
            stdlib.free(buf)
            buf = <char*> stdlib.malloc(bufsize)
            if buf is NULL:
                cpython.exc.PyErr_NoMemory()

            with nogil:
                ret = xattr.getxattr(path, name, &buf, bufsize)

        if ret < 0:
            raise OSError(errno, os.strerror(errno), path)

        return PyBytes_FromStringAndSize(buf, ret)
    
    finally:
        stdlib.free(buf)
        

def init(operations_, char* mountpoint_, list args):
    '''Initialize and mount FUSE file system
            
    `operations_` has to be an instance of the `Operations` class (or another
    class defining the same methods).
    
    `args` has to be a list of strings. Valid options are listed in struct
    fuse_opt fuse_mount_opts[] (mount.c:68) and struct fuse_opt fuse_ll_opts[]
    (fuse_lowlevel_c:1526).
    '''

    log.debug('Initializing llfuse')

    from llfuse.operations import Operations
    if not isinstance(operations_, Operations):
        raise TypeError("first parameter must be Operations instance!")

    global operations
    global fuse_ops
    global mountpoint
    global session
    global channel

    mountpoint = mountpoint_
    operations = operations_
    fuse_args = make_fuse_args(args)

    log.debug('Calling fuse_mount')
    channel = fuse_mount(mountpoint, fuse_args)
    if not channel:
        raise RuntimeError('fuse_mount failed')

    log.debug('Calling fuse_lowlevel_new')
    init_fuse_ops()
    session = fuse_lowlevel_new(fuse_args, &fuse_ops, sizeof(fuse_ops), NULL)
    if not session:
        fuse_unmount(mountpoint, channel)
        raise RuntimeError("fuse_lowlevel_new() failed")

    log.debug('Calling fuse_set_signal_handlers')
    if fuse_set_signal_handlers(session) == -1:
        fuse_session_destroy(session)
        fuse_unmount(mountpoint, channel)
        raise RuntimeError("fuse_set_signal_handlers() failed")

    log.debug('Calling fuse_session_add_chan')
    fuse_session_add_chan(session, channel)

def main(single=False):
    '''Run FUSE main loop'''

    if session == NULL:
        raise RuntimeError('Need to call init() before main()')

    if single:
        log.debug('Calling fuse_session_loop')
        # We need to unlock even in single threaded mode, because the
        # Operations methods will always try to acquire the lock
        if fuse_session_loop(session) != 0:
            raise RuntimeError("fuse_session_loop() failed")
    else:
        log.debug('Calling fuse_session_loop_mt')
        if fuse_session_loop_mt(session) != 0:
            raise RuntimeError("fuse_session_loop_mt() failed")

def close():
    '''Unmount file system and clean up'''

    global mountpoint
    global session
    global channel

    log.debug('Calling fuse_session_remove_chan')
    fuse_session_remove_chan(channel)
    log.debug('Calling fuse_remove_signal_handlers')
    fuse_remove_signal_handlers(session)
    log.debug('Calling fuse_session_destroy')
    fuse_session_destroy(session)
    log.debug('Calling fuse_unmount')
    fuse_unmount(mountpoint, channel)

    mountpoint = NULL
    session = NULL
    channel = NULL


lock = Lock.__new__(Lock)
lock_released = NoLockManager.__new__(NoLockManager)

####################
# INTERNAL FUNCTIONS
####################

log = logging.getLogger("fuse")

cdef object operations
cdef char* mountpoint = NULL
cdef fuse_session* session = NULL
cdef fuse_chan* channel = NULL
cdef fuse_lowlevel_ops fuse_ops


cdef object fill_entry_param(object attr, fuse_entry_param* entry):
    entry.ino = attr.st_ino
    entry.generation = attr.generation
    entry.entry_timeout = attr.entry_timeout
    entry.attr_timeout = attr.attry_timeout

    fill_c_stat(attr, &entry.attr)

cdef object fill_c_stat(object attr, c_stat* stat):
    stat.st_ino = attr.st_ino
    stat.st_mode = attr.st_mode
    stat.st_nlink = attr.st_nlink
    stat.st_uid = attr.st_uid
    stat.st_gid = attr.st_gid
    stat.st_rdev = attr.st_rdev
    stat.st_size = attr.st_size
    stat.st_blksize = attr.st_blksize
    stat.st_blocks = attr.st_blocks

    stat.st_atime = attr.st_atime
    stat.st_ctime = attr.st_ctime
    stat.st_mtime = attr.st_mtime
    
    SET_ATIME_NS(stat, (attr.st_atime - stat.st_atime) * 1e9)
    SET_CTIME_NS(stat, (attr.st_ctime - stat.st_ctime) * 1e9)
    SET_MTIME_NS(stat, (attr.st_mtime - stat.st_mtime) * 1e9)
    
cdef int handle_exc(char* fn, object e, fuse_req_t req):
    '''Try to call operations.handle_exc and fuse_reply_err'''
    
    log.exception('operations.%s() raised exception.', fn)
    try:
        with lock:
            operations.handle_exc(fn, e)
    except Exception as e:
        log.exception('operations.handle_exc() raised exception itself')

    if req is NULL:
        return 0
    else:
        return fuse_reply_err(req, errno.EIO)
        

cdef void init_fuse_ops():
    '''Initialize fuse_lowlevel_ops structure'''

    string.memset(&fuse_ops, 0, sizeof(fuse_lowlevel_ops))

    fuse_ops.init = fuse_init
    fuse_ops.destroy = fuse_destroy
    fuse_ops.lookup = fuse_lookup
    fuse_ops.forget = fuse_forget
    fuse_ops.getattr = fuse_getattr
    fuse_ops.setattr = fuse_setattr
    fuse_ops.readlink = fuse_readlink
    fuse_ops.mknod = fuse_mknod
    fuse_ops.mkdir = fuse_mkdir
    fuse_ops.unlink = fuse_unlink
    fuse_ops.rmdir = fuse_rmdir
    fuse_ops.symlink = fuse_symlink
    fuse_ops.rename = fuse_rename
    fuse_ops.link = fuse_link
    fuse_ops.open = fuse_open
    fuse_ops.read = fuse_read
    fuse_ops.write = fuse_write
    fuse_ops.flush = fuse_flush
    fuse_ops.release = fuse_release
    fuse_ops.fsync = fuse_fsync
    fuse_ops.opendir = fuse_opendir
    fuse_ops.readdir = fuse_readdir
    fuse_ops.releasedir = fuse_releasedir
    fuse_ops.fsyncdir = fuse_fsyncdir
    fuse_ops.statfs = fuse_statfs
    fuse_ops.setxattr = fuse_setxattr
    fuse_ops.getxattr = fuse_getxattr
    fuse_ops.listxattr = fuse_listxattr
    fuse_ops.removexattr = fuse_removexattr
    fuse_ops.access = fuse_access
    fuse_ops.create = fuse_create

cdef fuse_args_t* make_fuse_args(list args):
    cdef fuse_args_t* fuse_args
    fuse_args = <fuse_args_t*> stdlib.malloc(sizeof(fuse_args_t))

    if fuse_args is NULL:
        cpython.exc.PyErr_NoMemory()
        
    try:
        fuse_args.allocated = 1
        fuse_args.argc = len(args)
        fuse_args.argv = <char**> stdlib.malloc(fuse_args.argc * sizeof(char*))

        if fuse_args.argv is NULL:
            cpython.exc.PyErr_NoMemory()

        try:
            for (i, arg) in enumerate(args):
                fuse_args.argv[i] = PyBytes_AsString(arg)

            return fuse_args
        except:
            stdlib.free(fuse_args.argv)
            raise
    except:
        stdlib.free(fuse_args)
        raise

    
cdef class Lock:
    '''
    This is the class of lock itself as well as a context manager to
    execute code while the global lock is being held.
    '''

    def __init__(self):
        raise TypeError('You should not instantiate this class, use the '
                        'provided instance instead.')

    def acquire(self):
        '''Acquire global lock'''
        
        cdef int ret
        with nogil:
            ret = acquire()

        if ret == 0:
            return
        elif ret == EDEADLK:
            raise RuntimeError("Global lock cannot be acquired more than once")
        else:
            raise RuntimeError("pthread_lock_mutex returned errorcode %d" % ret)

    def release(self, *a):
        '''Release global lock'''
        
        cdef int ret
        with nogil:
            ret = release()
            
        if ret == 0:
            return
        elif ret == EPERM:
            raise RuntimeError("Global lock can only be released by the holding thread")
        else:
            raise RuntimeError("pthread_unlock_mutex returned errorcode %d" % ret)

    def yield_(self):
        '''Yield global lock to a different thread'''

        cdef int ret1, ret2

        with nogil:
            ret1 = release()
            if ret1 ==  0:
                sched_yield()
                ret2 = acquire()

        if ret1 != 0:
            if ret1 == EPERM:
                raise RuntimeError("Global lock can only be released by the holding thread")
            else:
                raise RuntimeError("pthread_unlock_mutex returned errorcode %d" % ret1)
        elif ret2 != 0:
            raise RuntimeError("pthread_lock_mutex returned errorcode %d" % ret2)

    __enter__ = acquire
    __exit__ = release


cdef class NoLockManager:
    '''Context manager to execute code while the global lock is released'''

    def __init__(self):
        raise TypeError('You should not instantiate this class, use the '
                        'provided instance instead.')

    def __enter__ (self):
        lock.release()
        
    def __exit__(self, *a):
        lock.acquire()



    
###############################
# PYTHON CLASSES AND EXCEPTIONS
###############################
        

cdef class RequestContext:
    '''
    Instances of this class provide information about the caller
    of the syscall that triggered a request.
    '''

    __slots__ = [ 'uid', 'pid', 'gid', 'umask' ]

    def __init__(self):
        for name in __slots__:
            setattr(self, name, None)

cdef class EntryAttributes:
    '''
    Instances of this class store attributes of directory entries.
    Most of the attributes correspond to the elements of the ``stat``
    C struct as returned by e.g. ``fstat``.
    
    Note that the  *st_Xtime* attributes support floating point numbers to
    allow for nanosecond resolution.
    '''

    # Attributes are documented in rst/operations.rst
    
    __slots__ = [ 'ino', 'generation', 'entry_timeout',
                  'attr_timeout', 'st_mode', 'st_nlink', 'st_uid', 'st_gid',
                  'st_rdev', 'st_size', 'st_blksize', 'st_blocks',
                  'st_atime', 'st_mtime', 'st_ctime' ]


    def __init__(self):
        for name in __slots__:
            setattr(self, name, None)
      
        
class FUSEError(Exception):
    '''Wrapped errno value to be returned to the fuse kernel module

    This exception can store only an errno. Request handlers should raise
    it to return a specific errno to the fuse kernel module.
    '''

    __slots__ = [ 'errno' ]

    def __init__(self, errno_):
        super(FUSEError, self).__init__()
        self.errno = errno_

    def __str__(self):
        # errno may not have strings for all error codes
        return errno.errorcode.get(self.errno, str(self.errno))

    
class Operations(object):
    '''
    This class defines the general and request handler methods that an
    LLFUSE file system may implement. If a particular request handler
    has not been implemented, it must raise `FUSEError(errno.ENOSYS)`.

    It has recommended that file systems are derived from this class
    and only overwrite the handlers that they actually implement. (The
    default implementations defined in this class all just raise the
    not-implemented exception).

    The only exception that request handlers are allowed to raise is
    `FUSEError(errno)`. This will cause the specified errno to be
    returned by the syscall that is being handled.
    '''
    
    # This is a dummy class, so all the methods could of course
    # be functions
    #pylint: disable=R0201
    
    def handle_exc(self, fn, exc):
        '''Handle exceptions that occured during request processing. 
        
        This method will be called when things went seriously wrong.
        This includes e.g. bugs in LLFUSE itself or request handlers
        raising exceptions other than `FUSEError`, but *not* problems
        with sending the reply once the request has been processed.

        The type of the request that failed is passed in *fn*.
        '''
        
        pass
    
    def init(self):
        '''Initialize operations
        
        This function will be called just before the file system
        starts handling requests. It must not raise any exceptions
        (including `FUSEError`, since this method is not handling a
        particular syscall).
        '''
        
        pass
    
    def destroy(self):
        '''Clean up operations.
        
        This method will be called after the last request has been
        received and when the file system is about to be unmounted. It
        must not raise any exceptions (including `FUSEError`, since
        this method is not handling a particular syscall).
        '''
        
        pass

    def lookup(self, parent_inode, name):
        '''Look up a directory entry by name and get its attributes.
    
        If the entry does not exist, this method must raise
        `FUSEError(errno.ENOENT)`. Otherwise it must return an
        `EntryAttributes` instance (or any other object that has the
        same attributes).
        '''
        
        raise FUSEError(errno.ENOSYS)
    
    def readdir(self, fh, off):
        '''Read directory entries
        
        This method returns an iterator over the contents of directory `fh`,
        starting at the entry identified by `off`.
        
        The iterator yields tuples of the form ``(name, attr, next_)``, where
        ``attr` is an object with attributes corresponding to the elements of
        ``struct stat`` and ``next_`` gives an offset that can be passed as
        `off` to a successive `readdir()` call.
         
        Iteration may be stopped as soon as enough elements have been
        retrieved and does not have to be continued until `StopIteration`
        is raised.

        If entries are added or removed during a `readdir` cycle, they may
        or may not be returned. However, they will not cause other entries
        to be skipped or returned more than once.        
        '''
        
        raise FUSEError(errno.ENOSYS)
    
        
    def read(self, fh, off, size):
        '''Read `size` bytes from `fh` at position `off`
        
        Unless the file has been opened in direct_io mode or EOF is reached,
        this function  returns exactly `size` bytes. 
        '''
        
        raise FUSEError(errno.ENOSYS)
    
    def link(self, inode, new_parent_inode, new_name):
        '''Create a hard link.
    
        Returns an object with the attributes of the newly created directory
        entry. The attributes are the same as for `lookup`.
        '''
        
        raise FUSEError(errno.ENOSYS)
    
    def open(self, inode, flags):
        '''Open a file.
        
        Returns an (integer) file handle. `flags` is a bitwise or of the open flags
        described in open(2) and defined in the `os` module (with the exception of 
        ``O_CREAT``, ``O_EXCL``, ``O_NOCTTY`` and ``O_TRUNC``)
        '''
        
        raise FUSEError(errno.ENOSYS)
    
    def opendir(self, inode):
        '''Open a directory.
        
        Returns an (integer) file handle. 
        '''
        
        raise FUSEError(errno.ENOSYS)

    
    def mkdir(self, parent_inode, name, mode, ctx):
        '''Create a directory
    
        `ctx` must be a context object that contains pid, uid and primary gid of
        the requesting process.
        
        Returns an object with the attributes of the newly created directory
        entry. The attributes are the same as for `lookup`.
        '''
        
        raise FUSEError(errno.ENOSYS)

    def mknod(self, parent_inode, name, mode, rdev, ctx):
        '''Create (possibly special) file
    
        `ctx` must be a context object that contains pid, uid and primary gid of
        the requesting process.
        
        Returns an object with the attributes of the newly created directory
        entry. The attributes are the same as for `lookup`.
        '''
        
        raise FUSEError(errno.ENOSYS)

    

    def listxattr(self, inode):
        '''Get list of extended attribute names'''
        
        raise FUSEError(errno.ENOSYS)
    
    def getattr(self, inode):
        '''Get attributes for `inode`
    
        Returns an object with attributes corresponding to the elements in 
        ``struct stat`` as well as
        
        :attr_timeout: Validity timeout (in seconds) for the attributes
        
        The returned object must not be modified by the caller as this would
        affect the internal state of the file system.
        
        Note that the ``st_Xtime`` entries support floating point numbers to
        allow for nano second resolution.
        '''
        
        raise FUSEError(errno.ENOSYS)
    
    def getxattr(self, inode, name):
        '''Return extended attribute value
        
        If the attribute does not exist, raises `FUSEError(ENOATTR)`
        '''
        
        raise FUSEError(errno.ENOSYS)
 
    def access(self, inode, mode, ctx, get_sup_gids):
        '''Check if requesting process has `mode` rights on `inode`. 
        
        Returns a boolean value. `get_sup_gids` must be a function that returns
        a list of the supplementary group ids of the requester.
        
        `ctx` must be a context object that contains pid, uid and primary gid of
        the requesting process.
        '''
        
        raise FUSEError(errno.ENOSYS)
    
    def create(self, inode_parent, name, mode, ctx):
        '''Create a file and open it
                
        `ctx` must be a context object that contains pid, uid and 
        primary gid of the requesting process.
        
        Returns a tuple of the form ``(fh, attr)``. `fh` is
        integer file handle that is used to identify the open file and
        `attr` is an object similar to the one returned by `lookup`.
        '''
        
        raise FUSEError(errno.ENOSYS)

    def flush(self, fh):
        '''Handle close() syscall.
        
        May be called multiple times for the same open file (e.g. if the file handle
        has been duplicated).
                                                             
        This method also clears all locks belonging to the file handle's owner.
        '''
        
        raise FUSEError(errno.ENOSYS)
    
    def fsync(self, fh, datasync):
        '''Flush buffers for file `fh`
        
        If `datasync` is true, only the user data is flushed (and no meta data). 
        '''
        
        raise FUSEError(errno.ENOSYS)
    
    
    def fsyncdir(self, fh, datasync):  
        '''Flush buffers for directory `fh`
        
        If the `datasync` is true, then only the directory contents are flushed
        (and not the meta data about the directory itself).
        '''
        
        raise FUSEError(errno.ENOSYS)
        
    def readlink(self, inode):
        '''Return target of symbolic link'''
        
        raise FUSEError(errno.ENOSYS)
    
    def release(self, fh):
        '''Release open file
        
        This method must be called exactly once for each `open` call.
        '''
        
        raise FUSEError(errno.ENOSYS)
    
    def releasedir(self, fh):
        '''Release open directory
        
        This method must be called exactly once for each `opendir` call.
        '''
        
        raise FUSEError(errno.ENOSYS)
    
    def removexattr(self, inode, name):
        '''Remove extended attribute
        
        If the attribute does not exist, raises `FUSEError(ENOATTR)`
        '''
        
        raise FUSEError(errno.ENOSYS)
    
    def rename(self, inode_parent_old, name_old, inode_parent_new, name_new):
        '''Rename a directory entry'''
        
        raise FUSEError(errno.ENOSYS)
    
    def rmdir(self, inode_parent, name):
        '''Remove a directory'''
        
        raise FUSEError(errno.ENOSYS)
    
    def setattr(self, inode, attr):
        '''Change directory entry attributes
        
        `attr` must be an object with attributes corresponding to the attributes
        of ``struct stat``. `attr` may also include a new value for ``st_size``
        which means that the file should be truncated or extended.
        
        Returns an object with the new attributs of the directory entry, similar
        to the one returned by `getattr()`
        '''
        
        raise FUSEError(errno.ENOSYS)
    
    def setxattr(self, inode, name, value):
        '''Set an extended attribute.
        
        The attribute may or may not exist already.
        '''
        
        raise FUSEError(errno.ENOSYS)
    
    def statfs(self):
        '''Get file system statistics
        
        Returns a `dict` with keys corresponding to the attributes of 
        ``struct statfs``.
        '''
        
        raise FUSEError(errno.ENOSYS)
    
    def symlink(self, inode_parent, name, target, ctx):
        '''Create a symbolic link
        
        `ctx` must be a context object that contains pid, uid and 
        primary gid of the requesting process.
        
        Returns an object with the attributes of the newly created directory
        entry, similar to the one returned by `lookup`.
        '''
        
        raise FUSEError(errno.ENOSYS)
    
    def unlink(self, parent_inode, name):
        '''Remove a (possibly special) file'''
        
        raise FUSEError(errno.ENOSYS)
    
    def write(self, fh, off, data):
        '''Write data into an open file
        
        Returns the number of bytes written.
        Unless the file was opened in ``direct_io`` mode, this is always equal to
        `len(data)`. 
        '''
        
        raise FUSEError(errno.ENOSYS)
    
