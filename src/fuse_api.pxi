'''
fuse_api.pxi

This file defines the Python bindings to common FUSE API functions.
It is included by llfuse.pyx.

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.

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


def setxattr(path, name, bytes value, namespace='user'):
    '''Set extended attribute

    *path* and *name* have to be of type `str`. In Python 3.x, they may
    contain surrogates. *value* has to be of type `bytes`.

    Under FreeBSD, the *namespace* parameter may be set to *system* or *user* to
    select the namespace for the extended attribute. For other platforms, this
    parameter is ignored.

    In contrast the `os.setxattr` function from the standard library,
    the method provided by Python-LLFUSE is also available for non-Linux
    systems.
    '''

    if not isinstance(path, str_t):
        raise TypeError('*path* argument must be of type str')

    if not isinstance(name, str_t):
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
        cnamespace = EXTATTR_NAMESPACE_SYSTEM
    else:
        cnamespace = EXTATTR_NAMESPACE_USER

    path_b = str2bytes(path)
    name_b = str2bytes(name)
    PyBytes_AsStringAndSize(value, &cvalue, &len_)
    cpath = <char*> path_b
    cname = <char*> name_b

    with nogil:
        # len_ is guaranteed positive
        ret = setxattr_p(cpath, cname, cvalue, <size_t> len_, cnamespace)

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

    In contrast the `os.setxattr` function from the standard library,
    the method provided by Python-LLFUSE is also available for non-Linux
    systems.
    '''

    if not isinstance(path, str_t):
        raise TypeError('*path* argument must be of type str')

    if not isinstance(name, str_t):
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
        cnamespace = EXTATTR_NAMESPACE_SYSTEM
    else:
        cnamespace = EXTATTR_NAMESPACE_USER

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
            ret = getxattr_p(cpath, cname, buf, bufsize, cnamespace)

        if ret < 0 and errno.errno == errno.ERANGE:
            with nogil:
                ret = getxattr_p(cpath, cname, NULL, 0, cnamespace)
            if ret < 0:
                raise OSError(errno.errno, strerror(errno.errno), path)
            bufsize = <size_t> ret
            stdlib.free(buf)
            buf = <char*> stdlib.malloc(bufsize * sizeof(char))
            if buf is NULL:
                cpython.exc.PyErr_NoMemory()

            with nogil:
                ret = getxattr_p(cpath, cname, buf, bufsize, cnamespace)

        if ret < 0:
            raise OSError(errno.errno, strerror(errno.errno), path)

        return PyBytes_FromStringAndSize(buf, ret)

    finally:
        stdlib.free(buf)

# Default options:
#
# * splice_write just means to use splice if possible (i.e., if data is passed
#   in a fd), and can be overriden using FUSE_BUF_NO_SPLICE. So it's a good idea
#   to always activate it.
#
# * splice_read means that requests are spliced from the fuse fd to a
#   (thread-specific) intermediate pipe (this is presumably done to prevent the
#   write handler from reading part of the next request). If splice_read is not
#   set, fuse instead reads the whole request into memory and passes this buffer
#   along.  If we eventually read the request into a buffer anyway (as we have
#   to if we want to create a Python object), using splice_read() is thus
#   expected to *decrease* performance because of the intermediate pipe.
#
# * splice_move is a no-op as of Linux 2.6.21. However, it will become active as
#   soon as some problems with the initial implementation have been solved.  If
#   active, it's expected to improve performance because we move pages from the
#   page instead of copying them.
#
default_options = frozenset(('big_writes', 'nonempty', 'default_permissions',
                             'no_splice_read', 'splice_write', 'splice_move'))
def init(ops, mountpoint, options=default_options):
    '''Initialize and mount FUSE file system

    *ops* has to be an instance of the `Operations` class (or another
    class defining the same methods).

    *args* has to be a set of strings. `default_options` provides some
    reasonable defaults. It is recommended to use these options as a basis and
    add or remove options as necessary. For example::

        my_opts = set(llfuse.default_options)
        my_opts.add('allow_other')
        my_opts.discard('default_permissions')
        llfuse.init(ops, mountpoint, my_apts)

    Valid options are listed under ``struct
    fuse_opt fuse_mount_opts[]``
    (`mount.c:82 <https://github.com/libfuse/libfuse/blob/master/lib/mount.c#L82>`_)
    and ``struct fuse_opt fuse_ll_opts[]``
    (`fuse_lowlevel_c:2626 <https://github.com/libfuse/libfuse/blob/master/lib/fuse_lowlevel.c#L2626>`_).
    '''

    log.debug('Initializing llfuse')
    cdef fuse_args f_args

    if not isinstance(mountpoint, str_t):
        raise TypeError('*mountpoint_* argument must be of type str')

    global operations
    global fuse_ops
    global mountpoint_b
    global session
    global channel

    mountpoint_b = str2bytes(os.path.abspath(mountpoint))
    operations = ops

    make_fuse_args(options, &f_args)
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

    log.debug('Calling fuse_session_add_chan')
    fuse_session_add_chan(session, channel)

    pthread_mutex_init(&exc_info_mutex, NULL)

def main(workers=None):
    '''Run FUSE main loop

    *workers* specifies the number of threads that will process requests
    concurrently. If *workers* is `None`, llfuse will pick a reasonable
    number bigger than one.  If *workers* is ``1`` all requests will be
    processed by the thread calling `main`.

    This function will also start additional threads for internal purposes (even
    if *workers* is ``1``). These (and all worker threads) are guaranteed to
    have terminated when `main` returns.

    While this function is running, special signal handlers will be installed
    for the *SIGTERM*, *SIGINT* (Ctrl-C), *SIGHUP* and *SIGPIPE*
    signals. *SIGPIPE* will be ignored, while the other three signals will cause
    request processing to stop and the function to return.  *SIGINT* (Ctrl-C)
    will thus *not* result in a `KeyboardInterrupt` exception while this
    function is runnnig.

    When the function returns because the file system has received an unmount
    request it will return `None`. If it returns because it has received a
    signal, it will return the signal number.
    '''

    global exc_info
    global exit_reason

    if session == NULL:
        raise RuntimeError('Need to call init() before main()')

    if workers == 0:
        raise ValueError('No workers is not a good idea')

    if workers is None:
        # We may add some smartness here later.
        workers = 30

    # SIGKILL cannot be caught, so we can use it as a placeholder
    # for "regular exit".
    exit_reason = signal.SIGKILL
    with contextlib.ExitStack() as on_exit:
        set_signal_handlers()
        on_exit.callback(lambda: restore_signal_handlers())

        # Start notification handling thread
        t = threading.Thread(target=_notify_loop)
        t.daemon = True
        t.start()
        on_exit.callback(_notify_queue.put, None, block=True, timeout=5)

        on_exit.callback(lambda: fuse_session_reset(session))
        exc_info = None
        log.debug('Calling fuse_session_loop')
        if workers == 1:
            session_loop_single()
        else:
            session_loop_mt(workers)

    if exc_info:
        # Re-raise expression from request handler
        log.debug('Terminated main loop because request handler raised exception, re-raising..')
        tmp = exc_info
        exc_info = None

        # The explicit version check works around a Cython bug with
        # the 3-parameter version of the raise statement, c.f.
        # https://github.com/cython/cython/commit/a6195f1a44ab21f5aa4b2a1b1842dd93115a3f42
        if PY_MAJOR_VERSION < 3:
            raise tmp[0], tmp[1], tmp[2]
        else:
            raise tmp[1].with_traceback(tmp[2])

    if exit_reason == signal.SIGKILL:
        return None
    else:
        return exit_reason

cdef session_loop_single():
    cdef void* mem
    cdef size_t size

    size = fuse_chan_bufsize(channel)
    mem = calloc_or_raise(1, size)
    try:
        session_loop(mem, size)
    finally:
        stdlib.free(mem)

cdef session_loop(void* mem, size_t size):
    '''Process requests'''

    cdef int res
    cdef fuse_chan *ch
    cdef fuse_buf buf

    while not fuse_session_exited(session):
        ch = channel
        buf.mem = mem
        buf.size = size
        buf.pos = 0
        buf.flags = 0
        with nogil:
            pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, NULL);
            res = fuse_session_receive_buf(session, &buf, &ch)
            pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, NULL);

        if res == -errno.EINTR:
            continue
        elif res < 0:
            raise OSError(-res, 'fuse_session_receive_buf failed with '
                          + strerror(-res))
        elif res == 0:
            break

        fuse_session_process_buf(session, &buf, ch)

ctypedef struct worker_data_t:
    sem_t* sem
    int thread_no
    int started
    pthread_t thread_id
    void* buf
    size_t bufsize

cdef void* worker_start(void* data) with gil:
    cdef worker_data_t *wd
    cdef int res
    global exc_info

    wd = <worker_data_t*> data

    t = threading.current_thread()
    t.name = 'fuse-worker-%d' % (wd.thread_no+1,)

    try:
        session_loop(wd.buf, wd.bufsize)
    except:
        fuse_session_exit(session)
        log.error('FUSE worker thread %d terminated with exception, '
                  'aborting processing', wd.thread_id)
        res = pthread_mutex_lock(&exc_info_mutex)
        if res != 0:
            log.error('pthread_mutex_lock failed with %s',
                      strerror(res))
        if not exc_info:
            exc_info = sys.exc_info()
        else:
            log.exception('Only one exception can be re-raised, the following '
                          'exception will be lost:')
        pthread_mutex_unlock(&exc_info_mutex)
        if res != 0:
            log.error('pthread_mutex_ulock failed with %s',
                      strerror(res))

    finally:
        sem_post(wd.sem)

cdef session_loop_mt(workers):
    cdef worker_data_t *wd
    cdef sigset_t newset, oldset
    cdef int res, i
    cdef size_t bufsize
    cdef sem_t sem

    if sem_init(&sem, 0, 0) != 0:
        raise OSError(errno.errno, 'sem_init failed with '
                      + strerror(errno.errno))

    sigemptyset(&newset);
    sigaddset(&newset, signal.SIGTERM);
    sigaddset(&newset, signal.SIGINT);
    sigaddset(&newset, signal.SIGHUP);
    sigaddset(&newset, signal.SIGQUIT);

    PyEval_InitThreads()
    bufsize = fuse_chan_bufsize(channel)
    wd = <worker_data_t*> calloc_or_raise(workers, sizeof(worker_data_t))
    try:
        for i in range(workers):
            wd[i].sem = &sem
            wd[i].thread_no = i
            wd[i].bufsize = bufsize
            wd[i].buf = calloc_or_raise(1, bufsize)

            # Disable signal reception in new thread
            # (FUSE does the same, probably for a good reason)
            pthread_sigmask(SIG_BLOCK, &newset, &oldset)
            res = pthread_create(&wd[i].thread_id, NULL, &worker_start, wd+i)
            pthread_sigmask(SIG_SETMASK, &oldset, NULL)
            if res != 0:
                raise OSError(res, 'pthread_create failed with '
                              + strerror(res))
            wd[i].started = 1

        with nogil:
            while not fuse_session_exited(session):
                sem_wait(&sem) # also interrupted by signals

    finally:
        for i in range(workers):
            if wd[i].started:
                pthread_cancel(wd[i].thread_id)
                with nogil:
                    res = pthread_join(wd[i].thread_id, NULL)
                if res != 0:
                    log.error('pthread_join failed with: %s', strerror(res))

            if wd[i].buf != NULL:
                stdlib.free(wd[i].buf)

        stdlib.free(wd)


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

        # The explicit version check works around a Cython bug with
        # the 3-parameter version of the raise statement, c.f.
        # https://github.com/cython/cython/commit/a6195f1a44ab21f5aa4b2a1b1842dd93115a3f42
        if PY_MAJOR_VERSION < 3:
            raise tmp[0], tmp[1], tmp[2]
        else:
            raise tmp[1].with_traceback(tmp[2])

def invalidate_inode(fuse_ino_t inode, attr_only=False):
    '''Invalidate cache for *inode*

    Instructs the FUSE kernel module to forgot cached attributes and
    data (unless *attr_only* is True) for *inode*. This operation is
    carried out asynchronously, i.e. the method may return before the
    kernel has executed the request.
    '''

    cdef NotifyRequest req
    req = NotifyRequest.__new__(NotifyRequest)
    req.kind = NOTIFY_INVAL_INODE
    req.ino = inode
    req.attr_only = bool(attr_only)
    _notify_queue.put(req)

def invalidate_entry(fuse_ino_t inode_p, bytes name):
    '''Invalidate directory entry

    Instructs the FUSE kernel module to forget about the directory
    entry *name* in the directory with inode *inode_p*. This operation
    is carried out asynchronously, i.e. the method may return before
    the kernel has executed the request.
    '''

    cdef NotifyRequest req
    req = NotifyRequest.__new__(NotifyRequest)
    req.kind = NOTIFY_INVAL_ENTRY
    req.ino = inode_p
    req.name = name
    _notify_queue.put(req)

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

def notify_store(inode, offset, data):
    '''Store data in kernel page cache

    Sends *data* for the kernel to store it in the page cache for *inode* at
    *offset*. If this provides data beyond the current file size, the file is
    automatically extended.

    If this function raises an exception, the store may still have completed
    partially.
    '''

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
        ret = fuse_lowlevel_notify_store(channel, ino, off, &bufvec, 0)

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
