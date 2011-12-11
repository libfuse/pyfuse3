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
    cdef char* path_c
    
    path_c = PyBytes_AsString(path)
    with nogil:

        dirp = dirent.opendir(path_c)
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

        names.append(ent.d_name)
        
    with nogil:
        dirent.closedir(dirp)
    
    return names


def setxattr(path, name, value):
    '''Set extended attribute'''

    cdef int ret
    cdef Py_ssize_t len_
    cdef char *cvalue, *cname, *cpath

    PyBytes_AsStringAndSize(value, &cvalue, &len_)
    cname = PyBytes_AsString(name)
    cpath = PyBytes_AsString(path)

    with nogil:
        ret = xattr.setxattr(cpath, cname, cvalue, len_, 0)

    if ret != 0:
        raise OSError(errno.errno, strerror(errno.errno), path)


def getxattr(path, name, int size_guess=128):
    '''Get extended attribute
    
    If the caller knows the approximate size of the attribute value,
    it should be supplied in *size_guess*. If the guess turns out
    to be wrong, the system call has to be carried out three times
    (the first call will fail, the second determines the size and
    the third finally gets the value).
    '''

    cdef ssize_t ret
    cdef char *buf, *cname, *cpath
    cdef size_t bufsize

    cname = PyBytes_AsString(name)
    cpath = PyBytes_AsString(path)

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
        
def init(operations_, char* mountpoint_, list args):
    '''Initialize and mount FUSE file system
            
    *operations_* has to be an instance of the `Operations` class (or another
    class defining the same methods).
    
    *args* has to be a list of strings. Valid options are listed under ``struct
    fuse_opt fuse_mount_opts[]``
    (`mount.c:82 <http://fuse.git.sourceforge.net/git/gitweb.cgi?p=fuse/fuse;a=blob;f=lib/mount.c;h=224ae9d5f299e3e497475d24400587f031e41d78;hb=HEAD#l82>`_)
    and ``struct fuse_opt fuse_ll_opts[]``
    (`fuse_lowlevel_c:2209 <http://fuse.git.sourceforge.net/git/gitweb.cgi?p=fuse/fuse;a=blob;f=lib/fuse_lowlevel.c;h=a19d429fc51417f4d55797f6c8f10b7db316b1de;hb=HEAD#l2209>`_).
    '''

    log.debug('Initializing llfuse')
    cdef fuse_args f_args

    if not isinstance(operations_, Operations):
        raise TypeError("first parameter must be Operations instance!")

    global operations
    global fuse_ops
    global mountpoint
    global session
    global channel

    mountpoint = os.path.abspath(mountpoint_)
    operations = operations_

    # Initialize Python thread support
    PyEval_InitThreads()
    
    make_fuse_args(args, &f_args)
    log.debug('Calling fuse_mount')
    channel = fuse_mount(mountpoint, &f_args)
    if not channel:
        raise RuntimeError('fuse_mount failed')

    log.debug('Calling fuse_lowlevel_new')
    init_fuse_ops()
    session = fuse_lowlevel_new(&f_args, &fuse_ops, sizeof(fuse_ops), NULL)
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
    '''Run FUSE main loop
    
    Note that *single* merely enforces that at most one request
    handler runs at a time. The main loop may still start background
    threads to e.g. asynchronously send notifications submitted with
    `invalidate_entry` and `invalidate_inode`.
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

    If *unmount* is False, the only clean up operations are peformed,
    but the file system is not unmounted. As long as the file system
    process is still running, all requests will hang. Once the process
    has terminated, these (and all future) requests fail with
    ESHUTDOWN. 
    '''

    global mountpoint
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
        fuse_unmount(mountpoint, channel)
    else:
        fuse_chan_destroy(channel)

    mountpoint = None
    session = NULL
    channel = NULL

    # destroy handler may have given us an exception
    if exc_info:
        tmp = exc_info
        exc_info = None
        raise tmp[0], tmp[1], tmp[2]

def invalidate_inode(inode, attr_only=False):
    '''Invalidate cache for *inode*
    
    Instructs the FUSE kernel module to forgot cached attributes and
    data (unless *attr_only* is True) for *inode*.
    '''

    _notify_queue.put(inval_inode_req(inode, attr_only))
    
def invalidate_entry(inode_p, name):
    '''Invalidate directory entry

    Instructs the FUSE kernel module to forget about the
    directory entry *name* in the directory with inode *inode_p*
    '''

    _notify_queue.put(inval_entry_req(inode_p, name))

class RequestContext:
    '''
    Instances of this class provide information about the caller
    of the syscall that triggered a request. The attributes should be
    self-explanatory.
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
    '''Wrapped errno value to be returned to the fuse kernel module

    This exception can store only an errno. Request handlers should raise
    it to return a specific errno to the fuse kernel module.
    '''

    __slots__ = [ 'errno' ]

    def __init__(self, errno_):
        super(FUSEError, self).__init__()
        self.errno = errno_

    def __str__(self):
        return strerror(self.errno)
    

def get_ino_t_bytes():
    '''Return number of bytes available for inode numbers

    Attempts to use inode values that need more bytes will result in
    `OverflowError`.
    '''
    return min(sizeof(ino_t), sizeof(fuse_ino_t))

def get_off_t_bytes():
    '''Return number of bytes available for file offsets

    Attempts to use values whose representation needs more bytes will
    result in `OverflowError`.
    '''
    return sizeof(off_t)

