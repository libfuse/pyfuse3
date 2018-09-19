'''
fuse_api.pxi

This file defines the Python bindings to common FUSE API functions.
It is included by pyfuse3.pyx.

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

import trio

def listdir(path):
    '''Like `os.listdir`, but releases the GIL.

    This function returns an iterator over the directory entries in *path*.

    The returned values are of type :ref:`str <python:textseq>`. Surrogate
    escape coding (cf.  `PEP 383 <http://www.python.org/dev/peps/pep-0383/>`_)
    is used for directory names that do not have a string representation.
    '''

    if not isinstance(path, str):
        raise TypeError('*path* argument must be of type str')

    cdef dirent.DIR* dirp
    cdef dirent.dirent* res
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
            res = dirent.readdir(dirp)

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
        dirent.closedir(dirp)

    return names


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

cdef class _WorkerData:
    """For internal use by pyfuse3 only."""

    cdef int task_count
    cdef int task_serial
    cdef object read_queue
    cdef object write_queue
    cdef int active_readers
    cdef int active_writers

    def __init__(self):
        self.read_queue = trio.hazmat.ParkingLot()
        self.write_queue = trio.hazmat.ParkingLot()
        self.active_readers = 0
        self.active_writers = 0

    cdef get_name(self):
        self.task_serial += 1
        return 'pyfuse-%02d' % self.task_serial

cdef _WorkerData worker_data = _WorkerData()


async def _wait_fuse_readable():
    #name = trio.hazmat.current_task().name
    worker_data.active_readers += 1
    if worker_data.active_readers > 1:
    #    log.debug('%s: Resource busy, parking in read queue.', name)
        await worker_data.read_queue.park()

    # Our turn!
    #log.debug('%s: Waiting for fuse fd to become readable...', name)
    await trio.hazmat.wait_readable(session_fd)
    worker_data.active_readers -= 1

    #log.debug('%s: fuse fd readable, unparking next task.', name)
    worker_data.read_queue.unpark()


async def _wait_fuse_writable():
    #name = trio.hazmat.current_task().name
    worker_data.active_writers += 1
    if worker_data.active_writers > 1:
    #    log.debug('%s: Resource busy, parking in writ queue.', name)
        await worker_data.write_queue.park()

    # Our turn!
    #log.debug('%s: Waiting for fuse fd to become writable...', name)
    await trio.hazmat.wait_writable(session_fd)
    worker_data.active_writers -= 1

    #log.debug('%s: fuse fd writable, unparking next task.', name)
    worker_data.write_queue.unpark()

@async_wrapper
async def main(int min_tasks=1, int max_tasks=99):
    '''Run FUSE main loop'''

    if session == NULL:
        raise RuntimeError('Need to call init() before main()')

    # Start notification handling thread
    t = threading.Thread(target=_notify_loop)
    t.daemon = True
    t.start()
    try:
        async with trio.open_nursery() as nursery:
            worker_data.task_count = 1
            worker_data.task_serial = 1
            nursery.start_soon(_session_loop, nursery, min_tasks, max_tasks,
                               name=worker_data.get_name())
    finally:
        _notify_queue.put(None, block=True, timeout=5)

@async_wrapper
async def _session_loop(nursery, int min_tasks, int max_tasks):
    cdef int res
    cdef fuse_buf buf

    name = trio.hazmat.current_task().name

    buf.mem = NULL
    buf.size = 0
    buf.pos = 0
    buf.flags = 0
    while not fuse_session_exited(session):
        if len(worker_data.read_queue) > min_tasks:
            log.debug('%s: too many idle tasks (%d total, %d waiting), terminating.',
                      name, worker_data.task_count, len(worker_data.read_queue))
            break
        await _wait_fuse_readable()
        res = fuse_session_receive_buf(session, &buf)
        if not worker_data.read_queue and worker_data.task_count < max_tasks:
            worker_data.task_count += 1
            log.debug('%s: No tasks waiting, starting another worker (now %d total).',
                      name, worker_data.task_count)
            nursery.start_soon(_session_loop, nursery, min_tasks, max_tasks,
                               name=worker_data.get_name())

        if res == -errno.EINTR:
            continue
        elif res < 0:
            raise OSError(-res, 'fuse_session_receive_buf failed with '
                          + strerror(-res))
        elif res == 0:
            break

        # When fuse_session_process_buf() calls back into one of our handler
        # methods, the handler will start a co-routine and store it in
        # py_retval.
        log.debug('%s: processing request...', name)
        save_retval(None)
        fuse_session_process_buf(session, &buf)
        if py_retval is not None:
            await py_retval
        log.debug('%s: processing complete.', name)

    log.debug('%s: terminated', name)
    stdlib.free(buf.mem)
    worker_data.task_count -= 1

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


@cython.freelist(10)
cdef class ReaddirToken:
    cdef fuse_req_t req
    cdef char *buf_start
    cdef char *buf
    cdef size_t size

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
