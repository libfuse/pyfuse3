'''
fuse_api.pxi

This file defines the Python bindings to common FUSE API functions.
It is included by llfuse.pyx.

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of LLFUSE (http://python-llfuse.googlecode.com).
LLFUSE can be distributed under the terms of the GNU LGPL.
'''

def listdir(path):
    '''Like `os.listdir`, but releases the GIL.

    This function returns an iterator over the directory entries in
    *path*. The returned values are of type :ref:`str
    <python:textseq>` in both Python 2.x and 3.x.

    In Python 2.x :class:`str` is equivalent to `bytes` so all names
    can be represented. In Python 3.x, surrogate escape coding (cf.
    `PEP 383 <http://www.python.org/dev/peps/pep-0383/>`_) is used for
    directory names that do not have a string representation.
    '''

    if not isinstance(path, str_t):
        raise TypeError('*path* argument must be of type str')
    
    cdef dirent.DIR* dirp
    cdef dirent.dirent ent
    cdef dirent.dirent* res
    cdef int ret
    cdef char* buf
    
    path_b = str2bytes(path)
    buf = <char*> path_b
    
    with nogil:
        dirp = dirent.opendir(buf)

    if dirp == NULL:
        raise OSError(errno.errno, strerror(errno.errno), path)

    names = list()
    while True:
        errno.errno = 0
        with nogil:
            ret = dirent.readdir_r(dirp, &ent, &res)
            
        if ret != 0:
            raise OSError(errno.errno, strerror(errno.errno), path)
        if res is NULL:
            break
        if string.strcmp(ent.d_name, b'.') == 0 or string.strcmp(ent.d_name, b'..') == 0:
            continue

        names.append(bytes2str(PyBytes_FromString(ent.d_name)))
        
    with nogil:
        dirent.closedir(dirp)
    
    return names


def setxattr(path, name, bytes value):
    '''Set extended attribute

    *path* and *name* have to be of type `str`. In Python 3.x, they may
    contain surrogates. *value* has to be of type `bytes`.
    '''

    if not isinstance(path, str_t):
        raise TypeError('*path* argument must be of type str')

    if not isinstance(name, str_t):
        raise TypeError('*name* argument must be of type str')

    cdef int ret
    cdef Py_ssize_t len_
    cdef char *cvalue, *cpath, *cname

    path_b = str2bytes(path)
    name_b = str2bytes(name)
    PyBytes_AsStringAndSize(value, &cvalue, &len_)
    cpath = <char*> path_b
    cname = <char*> name_b
    
    with nogil:
        ret = xattr.setxattr(cpath, cname, cvalue, len_, 0)

    if ret != 0:
        raise OSError(errno.errno, strerror(errno.errno), path)


def getxattr(path, name, int size_guess=128):
    '''Get extended attribute

    *path* and *name* have to be of type `str`. In Python 3.x, they may
    contain surrogates. Returns a value of type `bytes`.
    
    If the caller knows the approximate size of the attribute value,
    it should be supplied in *size_guess*. If the guess turns out
    to be wrong, the system call has to be carried out three times
    (the first call will fail, the second determines the size and
    the third finally gets the value).
    '''

    if not isinstance(path, str_t):
        raise TypeError('*path* argument must be of type str')

    if not isinstance(name, str_t):
        raise TypeError('*name* argument must be of type str')

    cdef ssize_t ret
    cdef char *buf, *cpath, *cname
    cdef size_t bufsize

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
            ret = xattr.getxattr(cpath, cname, buf, bufsize)

        if ret < 0 and errno.errno == errno.ERANGE:
            with nogil:
                ret = xattr.getxattr(cpath, cname, NULL, 0)
            if ret < 0:
                raise OSError(errno.errno, strerror(errno.errno), path)
            bufsize = <size_t> ret
            stdlib.free(buf)
            buf = <char*> stdlib.malloc(bufsize * sizeof(char))
            if buf is NULL:
                cpython.exc.PyErr_NoMemory()

            with nogil:
                ret = xattr.getxattr(cpath, cname, buf, bufsize)

        if ret < 0:
            raise OSError(errno.errno, strerror(errno.errno), path)

        return PyBytes_FromStringAndSize(buf, ret)
    
    finally:
        stdlib.free(buf)
        
def init(ops, mountpoint, list args):
    '''Initialize and mount FUSE file system
            
    *ops* has to be an instance of the `Operations` class (or another
    class defining the same methods).
    
    *args* has to be a list of strings. Valid options are listed under ``struct
    fuse_opt fuse_mount_opts[]``
    (`mount.c:82 <http://fuse.git.sourceforge.net/git/gitweb.cgi?p=fuse/fuse;f=lib/mount.c;hb=HEAD#l82>`_)
    and ``struct fuse_opt fuse_ll_opts[]``
    (`fuse_lowlevel_c:2209 <http://fuse.git.sourceforge.net/git/gitweb.cgi?p=fuse/fuse;f=lib/fuse_lowlevel.c;hb=HEAD#l2532>`_).
    '''

    log.debug('Initializing llfuse')
    cdef fuse_args f_args

    if not isinstance(ops, Operations):
        raise TypeError("first parameter must be Operations instance!")

    if not isinstance(mountpoint, str_t):
        raise TypeError('*mountpoint_* argument must be of type str')

    global operations
    global fuse_ops
    global mountpoint_b
    global session
    global channel

    mountpoint_b = str2bytes(os.path.abspath(mountpoint))
    operations = ops

    # Initialize Python thread support
    PyEval_InitThreads()
    
    make_fuse_args(args, &f_args)
    log.debug('Calling fuse_mount')
    channel = fuse_mount(<char*>mountpoint_b, &f_args)
    if not channel:
        raise RuntimeError('fuse_mount failed')

    log.debug('Calling fuse_lowlevel_new')
    init_fuse_ops()
    session = fuse_lowlevel_new(&f_args, &fuse_ops, sizeof(fuse_ops), NULL)
    if not session:
        fuse_unmount(<char*>mountpoint_b, channel)
        raise RuntimeError("fuse_lowlevel_new() failed")

    log.debug('Calling fuse_set_signal_handlers')
    if fuse_set_signal_handlers(session) == -1:
        fuse_session_destroy(session)
        fuse_unmount(<char*>mountpoint_b, channel)
        raise RuntimeError("fuse_set_signal_handlers() failed")

    log.debug('Calling fuse_session_add_chan')
    fuse_session_add_chan(session, channel)

def main(single=False):
    '''Run FUSE main loop
    
    If *single* is True, all requests will be handled sequentially by
    the thread that has called `main`. If *single* is False, multiple
    worker threads will be started and work on requests concurrently.
    '''

    cdef int ret
    global exc_info
    
    if session == NULL:
        raise RuntimeError('Need to call init() before main()')

    # Start notification handling thread
    t = threading.Thread(target=_notify_loop)
    t.daemon = True
    t.start()

    exc_info = None

    if single:
        log.debug('Calling fuse_session_loop')
        with nogil:
            ret = fuse_session_loop(session)
        _notify_queue.put(None, block=True, timeout=5) # Stop notification thread
        if ret != 0:
            raise RuntimeError("fuse_session_loop failed")
    else:
        log.debug('Calling fuse_session_loop_mt')
        with nogil:
            ret = fuse_session_loop_mt(session)
        _notify_queue.put(None, block=True, timeout=5) # Stop notification thread
        if ret != 0:
            raise RuntimeError("fuse_session_loop_mt() failed")

    if exc_info:
        # Re-raise expression from request handler
        log.debug('Terminated main loop because request handler raised exception, re-raising..')
        tmp = exc_info
        exc_info = None
        raise tmp[0], tmp[1], tmp[2]

def close(unmount=True):
    '''Unmount file system and clean up

    If *unmount* is False, only clean up operations are peformed, but
    the file system is not unmounted. As long as the file system
    process is still running, all requests will hang. Once the process
    has terminated, these (and all future) requests fail with ESHUTDOWN.
    '''

    global mountpoint_b
    global session
    global channel
    global exc_info

    log.debug('Calling fuse_session_remove_chan')
    fuse_session_remove_chan(channel)
    log.debug('Calling fuse_remove_signal_handlers')
    fuse_remove_signal_handlers(session)
    log.debug('Calling fuse_session_destroy')
    fuse_session_destroy(session)

    if unmount:
        log.debug('Calling fuse_unmount')
        fuse_unmount(<char*>mountpoint_b, channel)
    else:
        fuse_chan_destroy(channel)

    mountpoint_b = None
    session = NULL
    channel = NULL

    # destroy handler may have given us an exception
    if exc_info:
        tmp = exc_info
        exc_info = None
        raise tmp[0], tmp[1], tmp[2]

def invalidate_inode(int inode, attr_only=False):
    '''Invalidate cache for *inode*
    
    Instructs the FUSE kernel module to forgot cached attributes and
    data (unless *attr_only* is True) for *inode*. This operation is
    carried out asynchronously, i.e. the method may return before the
    kernel has executed the request.
    '''

    _notify_queue.put(inval_inode_req(inode, attr_only))
    
def invalidate_entry(int inode_p, bytes name):
    '''Invalidate directory entry

    Instructs the FUSE kernel module to forget about the directory
    entry *name* in the directory with inode *inode_p*. This operation
    is carried out asynchronously, i.e. the method may return before
    the kernel has executed the request.
    '''

    _notify_queue.put(inval_entry_req(inode_p, name))

class RequestContext:
    '''
    Instances of this class are passed to some `Operations` methods to
    provide information about the caller of the syscall that initiated
    the request.
    '''

    __slots__ = [ 'uid', 'pid', 'gid', 'umask' ]

    def __init__(self):
        for name in self.__slots__:
            setattr(self, name, None)

class EntryAttributes:
    '''
    Instances of this class store attributes of directory entries.
    Most of the attributes correspond to the elements of the ``stat``
    C struct as returned by e.g. ``fstat`` and should be
    self-explanatory.
    
    Note that the  *st_Xtime* attributes support floating point numbers to
    allow for nanosecond resolution.

    Request handlers do not need to return objects that inherit from 
    `EntryAttributes` directly as long as they provide the required
    attributes.
    '''

    # Attributes are documented in rst/operations.rst
    
    __slots__ = [ 'st_ino', 'generation', 'entry_timeout',
                  'attr_timeout', 'st_mode', 'st_nlink', 'st_uid', 'st_gid',
                  'st_rdev', 'st_size', 'st_blksize', 'st_blocks',
                  'st_atime', 'st_mtime', 'st_ctime' ]


    def __init__(self):
        for name in self.__slots__:
            setattr(self, name, None)
      
class StatvfsData:
    '''
    Instances of this class store information about the file system.
    The attributes correspond to the elements of the ``statvfs``
    struct, see :manpage:`statvfs(2)` for details.
    
    Request handlers do not need to return objects that inherit from
    `StatvfsData` directly as long as they provide the required
    attributes.
    '''

    # Attributes are documented in rst/operations.rst
    
    __slots__ = [ 'f_bsize', 'f_frsize', 'f_blocks', 'f_bfree',
                  'f_bavail', 'f_files', 'f_ffree', 'f_favail' ]

    def __init__(self):
        for name in self.__slots__:
            setattr(self, name, None)
        
class FUSEError(Exception):
    '''
    This exception may be raised by request handlers to indicate that
    the requested operation could not be carried out. The system call
    that resulted in the request (if any) will then fail with error
    code *errno_*.
    '''

    __slots__ = [ 'errno' ]

    def __init__(self, errno_):
        super(FUSEError, self).__init__()
        self.errno = errno_

    def __str__(self):
        return strerror(self.errno)
    

def get_ino_t_bits():
    '''Return number of bits available for inode numbers

    Attempts to use inode values that need more bytes will result in
    `OverflowError`.
    '''
    return min(sizeof(ino_t), sizeof(fuse_ino_t)) * 8

def get_off_t_bits():
    '''Return number of bytes available for file offsets

    Attempts to use values whose representation needs more bytes will
    result in `OverflowError`.
    '''
    return sizeof(off_t) * 8

