'''
internal.pxi

This file defines functions and data structures that are used internally by
pyfuse3. It is included by __init__.pyx.

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

cdef void save_retval(object val):
    global py_retval
    if py_retval is not None and val is not None:
        log.error('py_retval was not awaited - please report a bug at '
                  'https://github.com/libfuse/pyfuse3/issues!')
    py_retval = val

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
    fuse_ops.readdirplus = fuse_readdirplus
    fuse_ops.releasedir = fuse_releasedir
    fuse_ops.fsyncdir = fuse_fsyncdir
    fuse_ops.statfs = fuse_statfs
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

    args_new = [ b'pyfuse3' ]
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

def _notify_loop():
    '''Process async invalidate_entry calls.'''

    while True:
        req = _notify_queue.get()
        if req is None:
            log.debug('terminating notify thread')
            break

        (inode_p, name, deleted, ignore_enoent) = req
        try:
            invalidate_entry(inode_p, name, deleted)
        except Exception as exc:
            if ignore_enoent and isinstance(exc, FileNotFoundError):
                pass
            else:
                log.exception('Failed to submit invalidate_entry request for '
                              'parent inode %d, name %s', req[0], req[1])

cdef str2bytes(s):
    '''Convert *s* to bytes'''

    return s.encode(fse, 'surrogateescape')

cdef bytes2str(s):
    '''Convert *s* to str'''

    return s.decode(fse, 'surrogateescape')

cdef strerror(int errno):
    try:
        return os.strerror(errno)
    except ValueError:
        return 'errno: %d' % errno

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

cdef void* calloc_or_raise(size_t nmemb, size_t size) except NULL:
    cdef void* mem
    mem = stdlib.calloc(nmemb, size)
    if mem is NULL:
        raise MemoryError()
    return mem

cdef class _WorkerData:
    """For internal use by pyfuse3 only."""

    cdef int task_count
    cdef int task_serial
    cdef object read_lock
    cdef int active_readers

    def __init__(self):
        self.read_lock = trio.Lock()
        self.active_readers = 0

    cdef get_name(self):
        self.task_serial += 1
        return 'pyfuse-%02d' % self.task_serial

# Delay initialization so that pyfuse3.asyncio can replace
# the trio module.
cdef _WorkerData worker_data

async def _wait_fuse_readable():
    '''Wait for FUSE fd to become readable

    Return True if the fd is readable, or False if the main loop
    should terminate.
    '''

    #name = trio.lowlevel.current_task().name
    worker_data.active_readers += 1
    try:
        #log.debug('%s: Waiting for read lock...', name)
        async with worker_data.read_lock:
            #log.debug('%s: Waiting for fuse fd to become readable...', name)
            if fuse_session_exited(session):
                log.debug('FUSE session exit flag set while waiting for FUSE fd '
                          'to become readable.')
                return False
            await trio.lowlevel.wait_readable(session_fd)
            #log.debug('%s: fuse fd readable, unparking next task.', name)
    except trio.ClosedResourceError:
        log.debug('FUSE fd about to be closed.')
        return False

    finally:
        worker_data.active_readers -= 1

    return True

@async_wrapper
async def _session_loop(nursery, int min_tasks, int max_tasks):
    cdef int res
    cdef fuse_buf buf

    name = trio.lowlevel.current_task().name

    buf.mem = NULL
    buf.size = 0
    buf.pos = 0
    buf.flags = 0
    while not fuse_session_exited(session):
        if worker_data.active_readers > min_tasks:
            log.debug('%s: too many idle tasks (%d total, %d waiting), terminating.',
                      name, worker_data.task_count, worker_data.active_readers)
            break

        if not await _wait_fuse_readable():
            break

        res = fuse_session_receive_buf(session, &buf)
        if not worker_data.active_readers and worker_data.task_count < max_tasks:
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
        #log.debug('%s: processing request...', name)
        save_retval(None)
        fuse_session_process_buf(session, &buf)
        if py_retval is not None:
            await py_retval
        #log.debug('%s: processing complete.', name)

    log.debug('%s: terminated', name)
    stdlib.free(buf.mem)
    worker_data.task_count -= 1
