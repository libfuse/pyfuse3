'''
misc.pxi

This file defines various functions that are used internally by
LLFUSE. It is included by llfuse.pyx.

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
'''

cdef int handle_exc(fuse_req_t req):
    '''Try to call fuse_reply_err and terminate main loop'''

    cdef int res
    global exc_info

    res = pthread_mutex_lock(&exc_info_mutex)
    if res != 0:
        log.error('pthread_mutex_lock failed with %s',
                  strerror(res))
    if not exc_info:
        exc_info = sys.exc_info()
        log.info('handler raised %s exception (%s), terminating main loop.',
                 exc_info[0], exc_info[1])
        fuse_session_exit(session)
    else:
        log.exception('Only one exception can be re-raised in `llfuse.main`, '
                      'the following exception will be lost')

    pthread_mutex_unlock(&exc_info_mutex)
    if res != 0:
        log.error('pthread_mutex_ulock failed with %s',
                  strerror(res))

    if req is NULL:
        return 0
    else:
        return fuse_reply_err(req, errno.EIO)

cdef object get_request_context(fuse_req_t req):
    '''Get RequestContext() object'''

    cdef const_fuse_ctx* context
    cdef RequestContext ctx

    context = fuse_req_ctx(req)
    ctx = RequestContext.__new__(RequestContext)
    ctx.pid = context.pid
    ctx.uid = context.uid
    ctx.gid = context.gid
    ctx.umask = context.umask

    return ctx

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
    ASSIGN_DARWIN(fuse_ops.setxattr, &fuse_setxattr_darwin)
    ASSIGN_DARWIN(fuse_ops.getxattr, &fuse_getxattr_darwin)
    ASSIGN_NOT_DARWIN(fuse_ops.setxattr, &fuse_setxattr)
    ASSIGN_NOT_DARWIN(fuse_ops.getxattr, &fuse_getxattr)
    fuse_ops.listxattr = fuse_listxattr
    fuse_ops.removexattr = fuse_removexattr
    fuse_ops.access = fuse_access
    fuse_ops.create = fuse_create
    fuse_ops.forget_multi = fuse_forget_multi
    fuse_ops.write_buf = fuse_write_buf

cdef make_fuse_args(args, fuse_args* f_args):
    cdef char* arg
    cdef int i
    cdef ssize_t size_s
    cdef size_t size

    args_new = [ b'Python-LLFUSE' ]
    for el in args:
        args_new.append(b'-o')
        args_new.append(el.encode('us-ascii'))
    args = args_new

    f_args.argc = <int> len(args)
    if f_args.argc == 0:
        f_args.argv = NULL
        return

    f_args.allocated = 1
    f_args.argv = <char**> stdlib.calloc(<size_t> f_args.argc, sizeof(char*))

    if f_args.argv is NULL:
        cpython.exc.PyErr_NoMemory()

    try:
        for (i, el) in enumerate(args):
            PyBytes_AsStringAndSize(el, &arg, &size_s)
            size = <size_t> size_s # guaranteed positive
            f_args.argv[i] = <char*> stdlib.malloc((size+1)*sizeof(char))

            if f_args.argv[i] is NULL:
                cpython.exc.PyErr_NoMemory()

            string.strncpy(f_args.argv[i], arg, size+1)
    except:
        for i in range(f_args.argc):
            # Freeing a NULL pointer (if this element has not been allocated
            # yet) is fine.
            stdlib.free(f_args.argv[i])
        stdlib.free(f_args.argv)
        raise

cdef class Lock:
    '''
    This is the class of lock itself as well as a context manager to
    execute code while the global lock is being held.
    '''

    def __init__(self):
        raise TypeError('You should not instantiate this class, use the '
                        'provided instance instead.')

    def acquire(self, timeout=None):
        '''Acquire global lock

        If *timeout* is not None, and the lock could not be acquired
        after waiting for *timeout* seconds, return False. Otherwise
        return True.
        '''

        cdef int ret
        cdef int timeout_c

        if timeout is None:
            timeout_c = 0
        else:
            timeout_c = timeout

        with nogil:
            ret = acquire(timeout_c)

        if ret == 0:
            return True
        elif ret == ETIMEDOUT and timeout != 0:
            return False
        elif ret == EDEADLK:
            raise RuntimeError("Global lock cannot be acquired more than once")
        elif ret == EPROTO:
            raise RuntimeError("Lock still taken after receiving unlock notification")
        elif ret == EINVAL:
            raise RuntimeError("Lock not initialized")
        else:
            raise RuntimeError(strerror(ret))

    def release(self):
        '''Release global lock'''

        cdef int ret
        with nogil:
            ret = release()

        if ret == 0:
             return
        elif ret == EPERM:
            raise RuntimeError("Lock can only be released by the holding thread")
        elif ret == EINVAL:
            raise RuntimeError("Lock not initialized")
        else:
            raise RuntimeError(strerror(ret))

    def yield_(self, count=1):
        '''Yield global lock to a different thread

        A call to `~Lock.yield_` is roughly similar to::

            for i in range(count):
                if no_threads_waiting_for(lock):
                    break
                lock.release()
                lock.acquire()

        However, when using `~Lock.yield_` it is guaranteed that the lock will
        actually be passed to a different thread (the above pseude-code may
        result in the same thread re-acquiring the lock *count* times).
        '''

        cdef int ret
        cdef int count_c

        count_c = count
        with nogil:
            ret = c_yield(count_c)

        if ret == 0:
            return
        elif ret == EPERM:
            raise RuntimeError("Lock can only be released by the holding thread")
        elif ret == EPROTO:
            raise RuntimeError("Lock still taken after receiving unlock notification")
        elif ret == ENOMSG:
            raise RuntimeError("Other thread didn't take lock")
        elif ret == EINVAL:
            raise RuntimeError("Lock not initialized")
        else:
            raise RuntimeError(strerror(ret))

    def __enter__(self):
        self.acquire()

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.release()


cdef class NoLockManager:
    '''Context manager to execute code while the global lock is released'''

    def __init__(self):
        raise TypeError('You should not instantiate this class, use the '
                        'provided instance instead.')

    def __enter__ (self):
        lock.release()

    def __exit__(self, *a):
        lock.acquire()

def _notify_loop():
    '''Read notifications from queue and send to FUSE kernel module'''

    cdef ssize_t len_
    cdef char *cname
    cdef NotifyRequest req

    while True:
        req = _notify_queue.get()
        if req is None:
            return

        if req.kind == NOTIFY_INVAL_INODE:
            if req.attr_only:
                with nogil:
                    fuse_lowlevel_notify_inval_inode(channel, req.ino, -1, 0)
            else:
                with nogil:
                    fuse_lowlevel_notify_inval_inode(channel, req.ino, 0, 0)
        elif req.kind == NOTIFY_INVAL_ENTRY:
            PyBytes_AsStringAndSize(req.name, &cname, &len_)
            with nogil:
                # len_ is guaranteed positive
                fuse_lowlevel_notify_inval_entry(channel, req.ino, cname,
                                                 <size_t> len_)
        else:
            raise RuntimeError("Weird request kind received: %d", req.kind)

cdef str2bytes(s):
    '''Convert *s* to bytes

    Under Python 2.x, just returns *s*. Under Python 3.x, converts
    to file system encoding using surrogateescape.
    '''

    if PY_MAJOR_VERSION < 3:
        return s
    else:
        return s.encode(fse, 'surrogateescape')

cdef bytes2str(s):
    '''Convert *s* to str

    Under Python 2.x, just returns *s*. Under Python 3.x, converts
    from file system encoding using surrogateescape.
    '''

    if PY_MAJOR_VERSION < 3:
        return s
    else:
        return s.decode(fse, 'surrogateescape')

cdef strerror(int errno):
    try:
        return os.strerror(errno)
    except ValueError:
        return 'errno: %d' % errno

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

@cython.freelist(10)
cdef class SetattrFields:
    '''
    `SetattrFields` instances are passed to the `~Operations.setattr` handler
    to specify which attributes should be updated.
    '''

    cdef readonly object update_atime
    cdef readonly object update_mtime
    cdef readonly object update_mode
    cdef readonly object update_uid
    cdef readonly object update_gid
    cdef readonly object update_size

    def __cinit__(self):
        self.update_atime = False
        self.update_mtime = False
        self.update_mode = False
        self.update_uid = False
        self.update_gid = False
        self.update_size = False

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
        '''Validity timeout for the name of the directory entry

        Floating point numbers may be used. Units are seconds.
        '''
        return self.fuse_param.attr_timeout
    @attr_timeout.setter
    def attr_timeout(self, val):
        self.fuse_param.attr_timeout = val

    @property
    def entry_timeout(self):
        '''Validity timeout for the attributes of the directory entry

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
        return (int(self.attr.st_atime) * 10**9 + GET_ATIME_NS(self.attr))
    @st_atime_ns.setter
    def st_atime_ns(self, val):
        self.attr.st_atime = val / 10**9
        SET_ATIME_NS(self.attr, val % 10**9)

    @property
    def st_mtime_ns(self):
        '''Time of last modification in (integer) nanoseconds'''
        return (int(self.attr.st_mtime) * 10**9 + GET_MTIME_NS(self.attr))
    @st_mtime_ns.setter
    def st_mtime_ns(self, val):
        self.attr.st_mtime = val / 10**9
        SET_MTIME_NS(self.attr, val % 10**9)

    @property
    def st_ctime_ns(self):
        '''Time of last inode modification in (integer) nanoseconds'''
        return (int(self.attr.st_ctime) * 10**9 + GET_CTIME_NS(self.attr))
    @st_ctime_ns.setter
    def st_ctime_ns(self, val):
        self.attr.st_ctime = val / 10**9
        SET_CTIME_NS(self.attr, val % 10**9)

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


# As of Cython 0.23.1, @cython.freelist cannot be used for
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
    cdef int errno_

    @property
    def errno(self):
        '''Error code to return to client process'''
        return self.errno_
    @errno.setter
    def errno(self, val):
        self.errno_ = val

    def __cinit__(self, errno):
        self.errno_ = errno

    def __str__(self):
        return strerror(self.errno_)

@cython.freelist(300)
cdef class NotifyRequest:
    cdef fuse_ino_t ino
    cdef char attr_only
    cdef object name
    cdef int kind

cdef PyBytes_from_bufvec(fuse_bufvec *src):
    cdef fuse_bufvec dst
    cdef size_t len_
    cdef ssize_t res

    len_ = fuse_buf_size(src) - src.off
    if len_ > PY_SSIZE_T_MAX:
        raise OverflowError('Value too long to convert to Python')
    buf = PyBytes_FromStringAndSize(NULL, <ssize_t> len_)
    dst.count = 1
    dst.idx = 0
    dst.off = 0
    dst.buf[0].mem = PyBytes_AS_STRING(buf)
    dst.buf[0].size = len_
    dst.buf[0].flags = 0
    res = fuse_buf_copy(&dst, src, 0)
    if res < 0:
        raise OSError(errno.errno, 'fuse_buf_copy failed with '
                      + strerror(errno.errno))
    elif <size_t> res < len_:
        # This is expected to be rare
        return buf[:res]
    else:
        return buf

cdef class VoidPtrCapsule:
    cdef void* ptr

cdef free_p(VoidPtrCapsule cap):
    stdlib.free(cap.ptr)

cdef inline encap_ptr(void *ptr):
    cdef VoidPtrCapsule cap
    cap = VoidPtrCapsule.__new__(VoidPtrCapsule)
    cap.ptr = ptr
    return cap

cdef void signal_handler(int sig, siginfo_t *si, void* ctx) nogil:
    global exit_reason
    if session != NULL:
        fuse_session_exit(session)
    exit_reason = sig

cdef int sigaction_p(int sig, sigaction_t *sa,
                     sigaction_t *old_sa) except -1:
    cdef int res
    res = sigaction(sig, sa, old_sa)
    if res != 0:
        raise OSError(errno.errno, 'sigaction failed with '
                      + strerror(errno.errno))
    return 0

cdef sigaction_t sa_backup[4]
cdef set_signal_handlers():
    cdef sigaction_t sa

    sigemptyset(&sa.sa_mask)
    sa.sa_sigaction = &signal_handler
    sa.sa_flags = SA_SIGINFO
    sigaction_p(signal.SIGTERM, &sa, &sa_backup[0])
    sigaction_p(signal.SIGINT, &sa, &sa_backup[1])
    sigaction_p(signal.SIGHUP, &sa, &sa_backup[2])

    sa.sa_handler = signal.SIG_IGN
    sa.sa_flags = 0
    sigaction_p(signal.SIGPIPE, &sa, &sa_backup[3])

cdef restore_signal_handlers():
    sigaction_p(signal.SIGTERM, &sa_backup[0], NULL)
    sigaction_p(signal.SIGINT, &sa_backup[1], NULL)
    sigaction_p(signal.SIGHUP, &sa_backup[2], NULL)
    sigaction_p(signal.SIGPIPE, &sa_backup[3], NULL)

cdef void* calloc_or_raise(size_t nmemb, size_t size) except NULL:
    cdef void* mem
    mem = stdlib.calloc(nmemb, size)
    if mem is NULL:
        raise MemoryError()
    return mem
