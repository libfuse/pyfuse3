'''
fuse_api.pxi

This file defines the Python bindings to common FUSE API functions.
It is included by llfuse.pyx.

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of LLFUSE (http://python-llfuse.googlecode.com).
LLFUSE can be distributed under the terms of the GNU LGPL.
'''


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

    
