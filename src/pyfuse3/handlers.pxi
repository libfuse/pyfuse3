'''
handlers.pxi

This file defines the FUSE request handlers. It is included
by __init__.pyx.

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

@cython.freelist(60)
cdef class _Container:
    """For internal use by pyfuse3 only."""

    # This serves as a generic container to pass C variables
    # through Python. Which fields have valid data depends on
    # context.

    cdef dev_t    rdev
    cdef fuse_file_info fi
    cdef fuse_ino_t ino
    cdef fuse_ino_t parent
    cdef fuse_req_t req
    cdef int      flags
    cdef mode_t   mode
    cdef off_t    off
    cdef size_t   size
    cdef struct_stat stat
    cdef uint64_t fh

cdef void fuse_init (void *userdata, fuse_conn_info *conn):
    if not conn.capable & FUSE_CAP_READDIRPLUS:
        raise RuntimeError('Kernel too old, pyfuse3 requires kernel 3.9 or newer!')
    conn.want &= ~(<unsigned> FUSE_CAP_READDIRPLUS_AUTO)

    if (operations.supports_dot_lookup and
        conn.capable & FUSE_CAP_EXPORT_SUPPORT):
        conn.want |= FUSE_CAP_EXPORT_SUPPORT
    if (operations.enable_writeback_cache and
        conn.capable & FUSE_CAP_WRITEBACK_CACHE):
        conn.want |= FUSE_CAP_WRITEBACK_CACHE
    if (operations.enable_acl and
        conn.capable & FUSE_CAP_POSIX_ACL):
        conn.want |= FUSE_CAP_POSIX_ACL

    # Blocking rather than async, in case we decide to let the
    # init handler modify `conn` in the future.
    operations.init()

cdef void fuse_lookup (fuse_req_t req, fuse_ino_t parent,
                       const_char *name):
    cdef _Container c = _Container()
    c.req = req
    c.parent = parent
    save_retval(fuse_lookup_async(c, PyBytes_FromString(name)))

async def fuse_lookup_async (_Container c, name):
    cdef EntryAttributes entry
    cdef int ret

    ctx = get_request_context(c.req)
    try:
        entry = <EntryAttributes?> await operations.lookup(
            c.parent, name, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_entry(c.req, &entry.fuse_param)

    if ret != 0:
        log.error('fuse_lookup(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_forget (fuse_req_t req, fuse_ino_t ino,
                       uint64_t nlookup):
    save_retval(operations.forget([(ino, nlookup)]))
    fuse_reply_none(req)


cdef void fuse_forget_multi(fuse_req_t req, size_t count,
                            fuse_forget_data *forgets):
    forget_list = list()
    for el in forgets[:count]:
        forget_list.append((el.ino, el.nlookup))
    save_retval(operations.forget(forget_list))
    fuse_reply_none(req)


cdef void fuse_getattr (fuse_req_t req, fuse_ino_t ino,
                        fuse_file_info *fi):
    cdef _Container c = _Container()
    c.req = req
    c.ino = ino
    save_retval(fuse_getattr_async(c))

async def fuse_getattr_async (_Container c):
    cdef int ret
    cdef EntryAttributes entry

    ctx = get_request_context(c.req)
    try:
        entry = <EntryAttributes?> await operations.getattr(c.ino, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_attr(c.req, entry.attr, entry.fuse_param.attr_timeout)

    if ret != 0:
        log.error('fuse_getattr(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_setattr (fuse_req_t req, fuse_ino_t ino, struct_stat *stat,
                        int to_set, fuse_file_info *fi):
    cdef _Container c = _Container()
    c.req = req
    c.ino = ino
    c.stat = stat[0]
    c.flags = to_set
    if fi is NULL:
        fh = None
    else:
        fh = fi.fh
    save_retval(fuse_setattr_async(c, fh))

async def fuse_setattr_async (_Container c, fh):
    cdef int ret
    cdef timespec now
    cdef EntryAttributes entry
    cdef SetattrFields fields
    cdef struct_stat *attr
    cdef int to_set = c.flags

    ctx = get_request_context(c.req)
    entry = EntryAttributes()
    fields = SetattrFields.__new__(SetattrFields)
    string.memcpy(entry.attr, &c.stat, sizeof(struct_stat))

    attr = entry.attr
    if to_set & (FUSE_SET_ATTR_ATIME_NOW | FUSE_SET_ATTR_MTIME_NOW):
        ret = libc_extra.gettime_realtime(&now)
        if ret != 0:
            log.error('fuse_setattr(): clock_gettime(CLOCK_REALTIME) failed with %s',
                      strerror(errno.errno))

    if to_set & FUSE_SET_ATTR_ATIME:
        fields.update_atime = True
    elif to_set & FUSE_SET_ATTR_ATIME_NOW:
        fields.update_atime = True
        attr.st_atime = now.tv_sec
        SET_ATIME_NS(attr, now.tv_nsec)

    if to_set & FUSE_SET_ATTR_MTIME:
        fields.update_mtime = True
    elif to_set & FUSE_SET_ATTR_MTIME_NOW:
        fields.update_mtime = True
        attr.st_mtime = now.tv_sec
        SET_MTIME_NS(attr, now.tv_nsec)

    fields.update_ctime = bool(to_set & FUSE_SET_ATTR_CTIME)
    fields.update_mode = bool(to_set & FUSE_SET_ATTR_MODE)
    fields.update_uid = bool(to_set & FUSE_SET_ATTR_UID)
    fields.update_gid = bool(to_set & FUSE_SET_ATTR_GID)
    fields.update_size = bool(to_set & FUSE_SET_ATTR_SIZE)

    try:
        entry = <EntryAttributes?> await operations.setattr(c.ino, entry, fields, fh, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_attr(c.req, entry.attr, entry.fuse_param.attr_timeout)

    if ret != 0:
        log.error('fuse_setattr(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_readlink (fuse_req_t req, fuse_ino_t ino):
    cdef _Container c = _Container()
    c.req = req
    c.ino = ino
    save_retval(fuse_readlink_async(c))

async def fuse_readlink_async (_Container c):
    cdef int ret
    cdef char* name
    ctx = get_request_context(c.req)
    try:
        target = await operations.readlink(c.ino, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        name = PyBytes_AsString(target)
        ret = fuse_reply_readlink(c.req, name)

    if ret != 0:
        log.error('fuse_readlink(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_mknod (fuse_req_t req, fuse_ino_t parent, const_char *name,
                      mode_t mode, dev_t rdev):
    cdef _Container c = _Container()
    c.req = req
    c.parent = parent
    c.mode = mode
    c.rdev = rdev
    save_retval(fuse_mknod_async(c, PyBytes_FromString(name)))

async def fuse_mknod_async (_Container c, name):
    cdef int ret
    cdef EntryAttributes entry

    ctx = get_request_context(c.req)
    try:
        entry = <EntryAttributes?> await operations.mknod(
            c.parent, name, c.mode, c.rdev, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_entry(c.req, &entry.fuse_param)

    if ret != 0:
        log.error('fuse_mknod(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_mkdir (fuse_req_t req, fuse_ino_t parent, const_char *name,
                      mode_t mode):
    cdef _Container c = _Container()
    c.req = req
    c.parent = parent
    c.mode = mode
    save_retval(fuse_mkdir_async(c, PyBytes_FromString(name)))

async def fuse_mkdir_async (_Container c, name):
    cdef int ret
    cdef EntryAttributes entry

    # Force the entry type to directory. We need to explicitly cast,
    # because on BSD the S_* are not of type mode_t.
    c.mode = (c.mode & ~ <mode_t> S_IFMT) | <mode_t> S_IFDIR
    ctx = get_request_context(c.req)
    try:
        entry = <EntryAttributes?> await operations.mkdir(
            c.parent, name, c.mode, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_entry(c.req, &entry.fuse_param)

    if ret != 0:
        log.error('fuse_mkdir(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_unlink (fuse_req_t req, fuse_ino_t parent, const_char *name):
    cdef _Container c = _Container()
    c.req = req
    c.parent = parent
    save_retval(fuse_unlink_async(c, PyBytes_FromString(name)))

async def fuse_unlink_async (_Container c, name):
    cdef int ret

    ctx = get_request_context(c.req)
    try:
        await operations.unlink(c.parent, name, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_err(c.req, 0)

    if ret != 0:
        log.error('fuse_unlink(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_rmdir (fuse_req_t req, fuse_ino_t parent, const_char *name):
    cdef _Container c = _Container()
    c.req = req
    c.parent = parent
    save_retval(fuse_rmdir_async(c, PyBytes_FromString(name)))

async def fuse_rmdir_async (_Container c, name):
    cdef int ret

    ctx = get_request_context(c.req)
    try:
        await operations.rmdir(c.parent, name, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_err(c.req, 0)

    if ret != 0:
        log.error('fuse_rmdir(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_symlink (fuse_req_t req, const_char *link, fuse_ino_t parent,
                        const_char *name):
    cdef _Container c = _Container()
    c.req = req
    c.parent = parent
    save_retval(fuse_symlink_async(
        c, PyBytes_FromString(name), PyBytes_FromString(link)))

async def fuse_symlink_async (_Container c, name, link):
    cdef int ret
    cdef EntryAttributes entry

    ctx = get_request_context(c.req)
    try:
        entry = <EntryAttributes?> await operations.symlink(
            c.parent, name, link, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_entry(c.req, &entry.fuse_param)

    if ret != 0:
        log.error('fuse_symlink(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_rename (fuse_req_t req, fuse_ino_t parent, const_char *name,
                       fuse_ino_t newparent, const_char *newname, unsigned flags):
    cdef _Container c = _Container()
    c.req = req
    c.parent = parent
    c.ino = newparent
    c.flags = <int> flags
    save_retval(fuse_rename_async(
        c, PyBytes_FromString(name), PyBytes_FromString(newname)))


async def fuse_rename_async (_Container c, name, newname):
    cdef int ret
    cdef unsigned flags = <unsigned> c.flags
    cdef fuse_ino_t newparent = c.ino

    ctx = get_request_context(c.req)
    try:
        await operations.rename(c.parent, name, newparent, newname, flags, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_err(c.req, 0)

    if ret != 0:
        log.error('fuse_rename(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_link (fuse_req_t req, fuse_ino_t ino, fuse_ino_t newparent,
                     const_char *newname):
    cdef _Container c = _Container()
    c.req = req
    c.ino = ino
    c.parent = newparent
    save_retval(fuse_link_async(c, PyBytes_FromString(newname)))

async def fuse_link_async (_Container c, newname):
    cdef int ret
    cdef EntryAttributes entry

    ctx = get_request_context(c.req)
    try:
        entry = <EntryAttributes?> await operations.link(
            c.ino, c.parent, newname, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_entry(c.req, &entry.fuse_param)

    if ret != 0:
        log.error('fuse_link(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_open (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi):
    cdef _Container c = _Container()
    c.req = req
    c.ino = ino
    c.fi = fi[0]
    save_retval(fuse_open_async(c))

async def fuse_open_async (_Container c):
    cdef int ret
    cdef FileInfo fi

    ctx = get_request_context(c.req)

    try:
        fi = <FileInfo?> await operations.open(c.ino, c.fi.flags, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        fi._copy_to_fuse(&c.fi)
        ret = fuse_reply_open(c.req, &c.fi)

    if ret != 0:
        log.error('fuse_link(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_read (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                     fuse_file_info *fi):
    cdef _Container c = _Container()
    c.req = req
    c.size = size
    c.off = off
    c.fh = fi.fh
    save_retval(fuse_read_async(c))

async def fuse_read_async (_Container c):
    cdef int ret
    cdef Py_buffer pybuf

    try:
        buf = await operations.read(c.fh, c.off, c.size)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        PyObject_GetBuffer(buf, &pybuf, PyBUF_CONTIG_RO)
        ret = fuse_reply_buf(c.req, <const_char*> pybuf.buf, <size_t> pybuf.len)
        PyBuffer_Release(&pybuf)

    if ret != 0:
        log.error('fuse_read(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_write (fuse_req_t req, fuse_ino_t ino, const_char *buf,
                      size_t size, off_t off, fuse_file_info *fi):
    cdef _Container c = _Container()
    c.req = req
    c.size = size
    c.off = off
    c.fh = fi.fh

    if size > PY_SSIZE_T_MAX:
        raise OverflowError('Value too long to convert to Python')
    pbuf = PyBytes_FromStringAndSize(buf, <ssize_t> size)
    save_retval(fuse_write_async(c, pbuf))

async def fuse_write_async (_Container c, pbuf):
    cdef int ret
    cdef size_t len_

    try:
        len_ = await operations.write(c.fh, c.off, pbuf)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_write(c.req, len_)

    if ret != 0:
        log.error('fuse_write(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_write_buf(fuse_req_t req, fuse_ino_t ino, fuse_bufvec *bufv,
                         off_t off, fuse_file_info *fi):
    cdef _Container c = _Container()
    c.req = req
    c.off = off
    c.fh = fi.fh
    buf = PyBytes_from_bufvec(bufv)
    save_retval(fuse_write_buf_async(c, buf))

async def fuse_write_buf_async (_Container c, buf):
    cdef int ret
    cdef size_t len_

    try:
        len_ = await operations.write(c.fh, c.off, buf)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_write(c.req, len_)

    if ret != 0:
        log.error('fuse_write_buf(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_flush (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi):
    cdef _Container c = _Container()
    c.req = req
    c.fh = fi.fh
    save_retval(fuse_flush_async(c))

async def fuse_flush_async (_Container c):
    cdef int ret

    try:
        await operations.flush(c.fh)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_err(c.req, 0)

    if ret != 0:
        log.error('fuse_flush(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_release (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi):
    cdef _Container c = _Container()
    c.req = req
    c.fh = fi.fh
    save_retval(fuse_release_async(c))

async def fuse_release_async (_Container c):
    cdef int ret

    try:
        await operations.release(c.fh)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_err(c.req, 0)

    if ret != 0:
        log.error('fuse_release(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_fsync (fuse_req_t req, fuse_ino_t ino, int datasync,
                      fuse_file_info *fi):
    cdef _Container c = _Container()
    c.req = req
    c.flags = datasync
    c.fh = fi.fh
    save_retval(fuse_fsync_async(c))

async def fuse_fsync_async (_Container c):
    cdef int ret

    try:
        await operations.fsync(c.fh, c.flags != 0)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_err(c.req, 0)

    if ret != 0:
        log.error('fuse_fsync(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_opendir (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi):
    cdef _Container c = _Container()
    c.req = req
    c.ino = ino
    c.fi = fi[0]
    save_retval(fuse_opendir_async(c))

async def fuse_opendir_async (_Container c):
    cdef int ret

    ctx = get_request_context(c.req)
    try:
        c.fi.fh = await operations.opendir(c.ino, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_open(c.req, &c.fi)

    if ret != 0:
        log.error('fuse_opendir(): fuse_reply_* failed with %s', strerror(-ret))


@cython.freelist(10)
cdef class ReaddirToken:
    cdef fuse_req_t req
    cdef char *buf_start
    cdef char *buf
    cdef size_t size

cdef void fuse_readdirplus (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                            fuse_file_info *fi):
    global py_retval
    cdef _Container c = _Container()
    c.req = req
    c.size = size
    c.off = off
    c.fh = fi.fh
    save_retval(fuse_readdirplus_async(c))

async def fuse_readdirplus_async (_Container c):
    cdef int ret
    cdef ReaddirToken token = ReaddirToken()
    token.buf_start = NULL
    token.size = c.size
    token.req = c.req

    try:
        await operations.readdir(c.fh, c.off, token)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        if token.buf_start == NULL:
            ret = fuse_reply_buf(c.req, NULL, 0)
        else:
            ret = fuse_reply_buf(c.req, token.buf_start, c.size - token.size)
    finally:
        stdlib.free(token.buf_start)

    if ret != 0:
        log.error('fuse_readdirplus(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_releasedir (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi):
    cdef _Container c = _Container()
    c.req = req
    c.fh = fi.fh
    save_retval(fuse_releasedir_async(c))

async def fuse_releasedir_async (_Container c):
    cdef int ret

    try:
        await operations.releasedir(c.fh)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_err(c.req, 0)

    if ret != 0:
        log.error('fuse_releasedir(): fuse_reply_* failed with %s', strerror(-ret))



cdef void fuse_fsyncdir (fuse_req_t req, fuse_ino_t ino, int datasync,
                         fuse_file_info *fi):
    cdef _Container c = _Container()
    c.req = req
    c.flags = datasync
    c.fh = fi.fh
    save_retval(fuse_fsyncdir_async(c))

async def fuse_fsyncdir_async (_Container c):
    cdef int ret

    try:
        await operations.fsyncdir(c.fh, c.flags != 0)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_err(c.req, 0)

    if ret != 0:
        log.error('fuse_fsyncdir(): fuse_reply_* failed with %s', strerror(-ret))



cdef void fuse_statfs (fuse_req_t req, fuse_ino_t ino):
    cdef _Container c = _Container()
    c.req = req
    save_retval(fuse_statfs_async(c))

async def fuse_statfs_async (_Container c):
    cdef int ret
    cdef StatvfsData stats

    ctx = get_request_context(c.req)
    try:
        stats = <StatvfsData?> await operations.statfs(ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_statfs(c.req, &stats.stat)

    if ret != 0:
        log.error('fuse_statfs(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_setxattr (fuse_req_t req, fuse_ino_t ino, const_char *cname,
                         const_char *cvalue, size_t size, int flags):
    cdef _Container c = _Container()
    c.req = req
    c.ino = ino
    c.size = size
    c.flags = flags

    name = PyBytes_FromString(cname)
    if c.size > PY_SSIZE_T_MAX:
        raise OverflowError('Value too long to convert to Python')
    value = PyBytes_FromStringAndSize(cvalue, <ssize_t> c.size)

    save_retval(fuse_setxattr_async(c, name, value))

async def fuse_setxattr_async (_Container c, name, value):
    cdef int ret

    # Special case for deadlock debugging
    if c.ino == FUSE_ROOT_ID and name == 'fuse_stacktrace':
        operations.stacktrace()
        fuse_reply_err(c.req, 0)
        return

    # Make sure we know all the flags
    if c.flags & ~(libc_extra.XATTR_CREATE | libc_extra.XATTR_REPLACE):
        raise ValueError('unknown flag(s): %o' % c.flags)

    ctx = get_request_context(c.req)
    try:
        if c.flags & libc_extra.XATTR_CREATE: # Attribute must not exist
            try:
                await operations.getxattr(c.ino, name, ctx)
            except FUSEError as e:
                if e.errno != ENOATTR:
                    raise
            else:
                raise FUSEError(errno.EEXIST)

        elif c.flags & libc_extra.XATTR_REPLACE: # Attribute must exist
            await operations.getxattr(c.ino, name, ctx)

        await operations.setxattr(c.ino, name, value, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_err(c.req, 0)

    if ret != 0:
        log.error('fuse_setxattr(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_getxattr (fuse_req_t req, fuse_ino_t ino, const_char *name,
                         size_t size):
    cdef _Container c = _Container()
    c.req = req
    c.ino = ino
    c.size = size
    save_retval(fuse_getxattr_async(c, PyBytes_FromString(name)))

async def fuse_getxattr_async (_Container c, name):
    cdef int ret
    cdef ssize_t len_s
    cdef size_t len_
    cdef char *cbuf

    ctx = get_request_context(c.req)
    try:
        buf = await operations.getxattr(c.ino, name, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        PyBytes_AsStringAndSize(buf, &cbuf, &len_s)
        len_ = <size_t> len_s # guaranteed positive

        if c.size == 0:
            ret = fuse_reply_xattr(c.req, len_)
        elif len_ <= c.size:
            ret = fuse_reply_buf(c.req, cbuf, len_)
        else:
            ret = fuse_reply_err(c.req, errno.ERANGE)

    if ret != 0:
        log.error('fuse_getxattr(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_listxattr (fuse_req_t req, fuse_ino_t ino, size_t size):
    cdef _Container c = _Container()
    c.req = req
    c.ino = ino
    c.size = size
    save_retval(fuse_listxattr_async(c))

async def fuse_listxattr_async (_Container c):
    cdef int ret
    cdef ssize_t len_s
    cdef size_t len_
    cdef char *cbuf


    ctx = get_request_context(c.req)
    try:
        res = await operations.listxattr(c.ino, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        buf = b'\0'.join(res) + b'\0'

        PyBytes_AsStringAndSize(buf, &cbuf, &len_s)
        len_ = <size_t> len_s # guaranteed positive

        if len_ == 1: # No attributes
            len_ = 0

        if c.size == 0:
            ret = fuse_reply_xattr(c.req, len_)
        elif len_ <= c.size:
            ret = fuse_reply_buf(c.req, cbuf, len_)
        else:
            ret = fuse_reply_err(c.req, errno.ERANGE)

    if ret != 0:
        log.error('fuse_listxattr(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_removexattr (fuse_req_t req, fuse_ino_t ino, const_char *name):
    cdef _Container c = _Container()
    c.req = req
    c.ino = ino
    save_retval(fuse_removexattr_async(c, PyBytes_FromString(name)))

async def fuse_removexattr_async (_Container c, name):
    cdef int ret

    ctx = get_request_context(c.req)
    try:
        await operations.removexattr(c.ino, name, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        ret = fuse_reply_err(c.req, 0)

    if ret != 0:
        log.error('fuse_removexattr(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_access (fuse_req_t req, fuse_ino_t ino, int mask):
    cdef _Container c = _Container()
    c.req = req
    c.ino = ino
    c.flags = mask
    save_retval(fuse_access_async(c))

async def fuse_access_async (_Container c):
    cdef int ret
    cdef int mask = c.flags

    ctx = get_request_context(c.req)
    try:
        allowed = await operations.access(c.ino, mask, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        if allowed:
            ret = fuse_reply_err(c.req, 0)
        else:
            ret = fuse_reply_err(c.req, EACCES)

    if ret != 0:
        log.error('fuse_access(): fuse_reply_* failed with %s', strerror(-ret))



cdef void fuse_create (fuse_req_t req, fuse_ino_t parent, const_char *name,
                       mode_t mode, fuse_file_info *fi):
    cdef _Container c = _Container()
    c.req = req
    c.parent = parent
    c.mode = mode
    c.fi = fi[0]
    save_retval(fuse_create_async(c, PyBytes_FromString(name)))

async def fuse_create_async (_Container c, name):
    cdef int ret
    cdef EntryAttributes entry
    cdef FileInfo fi

    ctx = get_request_context(c.req)
    try:
        tmp = await operations.create(c.parent, name, c.mode, c.fi.flags, ctx)
    except FUSEError as e:
        ret = fuse_reply_err(c.req, e.errno)
    else:
        fi = <FileInfo?> tmp[0]
        entry = <EntryAttributes?> tmp[1]
        fi._copy_to_fuse(&c.fi)
        ret = fuse_reply_create(c.req, &entry.fuse_param, &c.fi)

    if ret != 0:
        log.error('fuse_create(): fuse_reply_* failed with %s', strerror(-ret))
