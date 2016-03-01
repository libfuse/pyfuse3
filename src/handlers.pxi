'''
handlers.pxi

This file defines the FUSE request handlers. It is included
by llfuse.pyx.

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
'''

cdef void fuse_init (void *userdata, fuse_conn_info *conn) with gil:
    try:
        with lock:
            operations.init()
    except:
        handle_exc(NULL)

cdef void fuse_destroy (void *userdata) with gil:
    global exc_info
    try:
        with lock:
            operations.destroy()
    except:
        if not exc_info:
            exc_info = sys.exc_info()
        else:
            log.exception('Exception after kill:')

cdef void fuse_lookup (fuse_req_t req, fuse_ino_t parent,
                       const_char *c_name) with gil:
    cdef EntryAttributes entry
    cdef int ret

    try:
        ctx = get_request_context(req)
        name = PyBytes_FromString(c_name)
        with lock:
            entry = <EntryAttributes?> operations.lookup(parent, name, ctx)
        ret = fuse_reply_entry(req, &entry.fuse_param)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_lookup(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_forget (fuse_req_t req, fuse_ino_t ino,
                       ulong_t nlookup) with gil:
    try:
        with lock:
            operations.forget([(ino, nlookup)])
    except:
        handle_exc(NULL)
    fuse_reply_none(req)


cdef void fuse_forget_multi(fuse_req_t req, size_t count,
                            fuse_forget_data *forgets) with gil:
    try:
        forget_list = list()
        for i in range(0, count):
            forget_list.append((forgets[i].ino, forgets[i].nlookup))
        with lock:
            operations.forget(forget_list)
    except:
        handle_exc(NULL)
    fuse_reply_none(req)

cdef void fuse_getattr (fuse_req_t req, fuse_ino_t ino,
                        fuse_file_info *fi) with gil:
    cdef int ret
    cdef EntryAttributes entry

    try:
        ctx = get_request_context(req)
        with lock:
            entry = <EntryAttributes?> operations.getattr(ino, ctx)

        ret = fuse_reply_attr(req, entry.attr, entry.fuse_param.attr_timeout)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_getattr(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_setattr (fuse_req_t req, fuse_ino_t ino, struct_stat *stat,
                        int to_set, fuse_file_info *fi) with gil:
    cdef int ret
    cdef timespec now
    cdef EntryAttributes entry
    cdef SetattrFields fields
    cdef struct_stat *attr

    try:
        ctx = get_request_context(req)
        entry = EntryAttributes()
        fields = SetattrFields.__new__(SetattrFields)
        string.memcpy(entry.attr, stat, sizeof(struct_stat))

        attr = entry.attr
        if to_set & (FUSE_SET_ATTR_ATIME_NOW | FUSE_SET_ATTR_MTIME_NOW):
            ret = gettime_realtime(&now)
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

        fields.update_mode = bool(to_set & FUSE_SET_ATTR_MODE)
        fields.update_uid = bool(to_set & FUSE_SET_ATTR_UID)
        fields.update_gid = bool(to_set & FUSE_SET_ATTR_GID)
        fields.update_size = bool(to_set & FUSE_SET_ATTR_SIZE)

        if fi is NULL:
            fh = None
        else:
            fh = fi.fh
        with lock:
            entry = <EntryAttributes?> operations.setattr(ino, entry, fields, fh, ctx)

        ret = fuse_reply_attr(req, entry.attr, entry.fuse_param.attr_timeout)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_setattr(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_readlink (fuse_req_t req, fuse_ino_t ino) with gil:
    cdef int ret
    cdef char* name
    try:
        ctx = get_request_context(req)
        with lock:
            target = operations.readlink(ino, ctx)
        name = PyBytes_AsString(target)
        ret = fuse_reply_readlink(req, name)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_readlink(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_mknod (fuse_req_t req, fuse_ino_t parent, const_char *name,
                      mode_t mode, dev_t rdev) with gil:
    cdef int ret
    cdef EntryAttributes entry

    try:
        ctx = get_request_context(req)
        with lock:
            entry = <EntryAttributes?> operations.mknod(parent, PyBytes_FromString(name),
                                                        mode, rdev, ctx)
        ret = fuse_reply_entry(req, &entry.fuse_param)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_mknod(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_mkdir (fuse_req_t req, fuse_ino_t parent, const_char *name,
                      mode_t mode) with gil:
    cdef int ret
    cdef EntryAttributes entry

    try:
        # Force the entry type to directory. We need to explicitly cast,
        # because on BSD the S_* are not of type mode_t.
        mode = (mode & ~ <mode_t> S_IFMT) | <mode_t> S_IFDIR
        ctx = get_request_context(req)
        with lock:
            entry = <EntryAttributes?> operations.mkdir(parent, PyBytes_FromString(name),
                                                        mode, ctx)
        ret = fuse_reply_entry(req, &entry.fuse_param)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_mkdir(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_unlink (fuse_req_t req, fuse_ino_t parent, const_char *name) with gil:
    cdef int ret

    try:
        ctx = get_request_context(req)
        with lock:
            operations.unlink(parent, PyBytes_FromString(name), ctx)
        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_unlink(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_rmdir (fuse_req_t req, fuse_ino_t parent, const_char *name) with gil:
    cdef int ret

    try:
        ctx = get_request_context(req)
        with lock:
            operations.rmdir(parent, PyBytes_FromString(name), ctx)
        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_rmdir(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_symlink (fuse_req_t req, const_char *link, fuse_ino_t parent,
                        const_char *name) with gil:
    cdef int ret
    cdef EntryAttributes entry

    try:
        ctx = get_request_context(req)
        with lock:
            entry = <EntryAttributes?> operations.symlink(parent, PyBytes_FromString(name),
                                                          PyBytes_FromString(link), ctx)
        ret = fuse_reply_entry(req, &entry.fuse_param)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_symlink(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_rename (fuse_req_t req, fuse_ino_t parent, const_char *name,
                       fuse_ino_t newparent, const_char *newname) with gil:
    cdef int ret

    try:
        ctx = get_request_context(req)
        with lock:
            operations.rename(parent, PyBytes_FromString(name),
                              newparent, PyBytes_FromString(newname), ctx)
        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_rename(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_link (fuse_req_t req, fuse_ino_t ino, fuse_ino_t newparent,
                     const_char *newname) with gil:
    cdef int ret
    cdef EntryAttributes entry

    try:
        ctx = get_request_context(req)
        with lock:
            entry = <EntryAttributes?> operations.link(ino, newparent,
                                                       PyBytes_FromString(newname), ctx)
        ret = fuse_reply_entry(req, &entry.fuse_param)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_link(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_open (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    cdef int ret

    try:
        ctx = get_request_context(req)
        with lock:
            fi.fh = operations.open(ino, fi.flags, ctx)

        # Cached file data does not need to be invalidated.
        # http://article.gmane.org/gmane.comp.file-systems.fuse.devel/5325/
        fi.keep_cache = 1

        ret = fuse_reply_open(req, fi)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_link(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_read (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                     fuse_file_info *fi) with gil:
    cdef int ret
    cdef Py_buffer pybuf

    try:
        with lock:
            buf = operations.read(fi.fh, off, size)

        PyObject_GetBuffer(buf, &pybuf, PyBUF_CONTIG_RO)
        with nogil:
            ret = fuse_reply_buf(req, <const_char*> pybuf.buf, <size_t> pybuf.len)
        PyBuffer_Release(&pybuf)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_read(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_write (fuse_req_t req, fuse_ino_t ino, const_char *buf,
                      size_t size, off_t off, fuse_file_info *fi) with gil:
    cdef int ret
    cdef size_t len_

    try:
        if size > PY_SSIZE_T_MAX:
            raise OverflowError('Value too long to convert to Python')
        pbuf = PyBytes_FromStringAndSize(buf, <ssize_t> size)

        # `with` statement may theoretically swallow exception, so we have to
        # initialize len_ to prevent gcc warning about it potentially
        # not initialized.
        len_ = 0
        with lock:
            len_ = operations.write(fi.fh, off, pbuf)
        ret = fuse_reply_write(req, len_)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_write(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_write_buf(fuse_req_t req, fuse_ino_t ino, fuse_bufvec *bufv,
                         off_t off, fuse_file_info *fi) with gil:
    cdef int ret
    cdef size_t len_

    try:
        # `with` statement may theoretically swallow exception, so we have to
        # initialize len_ to prevent gcc warning about it potentially
        # not initialized.
        len_ = 0

        buf = PyBytes_from_bufvec(bufv)
        with lock:
            len_ = operations.write(fi.fh, off, buf)
        ret = fuse_reply_write(req, len_)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_write_buf(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_flush (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    cdef int ret

    try:
        with lock:
            operations.flush(fi.fh)
        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_flush(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_release (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    cdef int ret

    try:
        with lock:
            operations.release(fi.fh)
        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_release(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_fsync (fuse_req_t req, fuse_ino_t ino, int datasync,
                      fuse_file_info *fi) with gil:
    cdef int ret

    try:
        with lock:
            operations.fsync(fi.fh, datasync != 0)
        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_fsync(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_opendir (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    cdef int ret

    try:
        ctx = get_request_context(req)
        with lock:
            fi.fh = operations.opendir(ino, ctx)

        ret = fuse_reply_open(req, fi)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_opendir(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_readdir (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                        fuse_file_info *fi) with gil:
    cdef int ret
    cdef char *cname
    cdef char *buf
    cdef size_t len_, acc_size
    cdef EntryAttributes entry

    try:
        acc_size = 0
        buf = NULL
        with lock:
            for (name, attr, next_) in operations.readdir(fi.fh, off):
                entry = <EntryAttributes?> attr
                if buf == NULL:
                    buf = <char*> calloc_or_raise(size, sizeof(char))
                cname = PyBytes_AsString(name)
                len_ = fuse_add_direntry(req, buf + acc_size, size - acc_size,
                                         cname, entry.attr, next_)
                if len_ > (size - acc_size):
                    break
                acc_size += len_
        ret = fuse_reply_buf(req, buf, acc_size)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)
    finally:
        if buf != NULL:
            stdlib.free(buf)

    if ret != 0:
        log.error('fuse_readdir(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_releasedir (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    cdef int ret

    try:
        with lock:
            operations.releasedir(fi.fh)
        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_releasedir(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_fsyncdir (fuse_req_t req, fuse_ino_t ino, int datasync,
                         fuse_file_info *fi) with gil:
    cdef int ret

    try:
        with lock:
            operations.fsyncdir(fi.fh, datasync != 0)
        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_fsyncdir(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_statfs (fuse_req_t req, fuse_ino_t ino) with gil:
    cdef int ret
    cdef StatvfsData stats

    # We don't set all the components
    try:
        ctx = get_request_context(req)
        with lock:
            stats = <StatvfsData?> operations.statfs(ctx)
        ret = fuse_reply_statfs(req, &stats.stat)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_statfs(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_setxattr_darwin (fuse_req_t req, fuse_ino_t ino, const_char *cname,
                                const_char *cvalue, size_t size, int flags,
                                uint32_t position) with gil:
    cdef int ret

    if position != 0:
        log.error('fuse_setxattr(): non-zero position (%d) not supported', position)
        ret = fuse_reply_err(req, errno.EIO)
        if ret != 0:
            log.error('fuse_setxattr(): fuse_reply_err failed with %s', strerror(-ret))
        return

    # Filter out flags that don't make any sense for a FUSE
    # file system, but that FUSE4x nevertheless stupidly
    # passes through.
    # (cf. https://groups.google.com/d/msg/fuse4x/bRnh7J_nsts/Z7raJ06DB4sJ)
    flags &= ~(XATTR_NOFOLLOW | XATTR_NODEFAULT |
               XATTR_NOSECURITY)
    fuse_setxattr(req, ino, cname, cvalue, size, flags)

cdef void fuse_setxattr (fuse_req_t req, fuse_ino_t ino, const_char *cname,
                         const_char *cvalue, size_t size, int flags) with gil:
    cdef int ret

    try:
        ctx = get_request_context(req)
        name = PyBytes_FromString(cname)
        if size > PY_SSIZE_T_MAX:
            raise OverflowError('Value too long to convert to Python')
        value = PyBytes_FromStringAndSize(cvalue, <ssize_t> size)

        # Special case for deadlock debugging
        if ino == FUSE_ROOT_ID and string.strcmp(cname, 'fuse_stacktrace') == 0:
            operations.stacktrace()
        else:
            if PLATFORM == PLATFORM_DARWIN:
                # No known flags
                with lock:
                    operations.setxattr(ino, name, value, ctx)
            else:
                # Make sure we know all the flags
                if flags & ~(XATTR_CREATE | XATTR_REPLACE):
                    raise ValueError('unknown flag(s): %o' % flags)

                with lock:
                    if flags & XATTR_CREATE: # Attribute must not exist
                        try:
                            operations.getxattr(ino, name)
                        except FUSEError as e:
                            if e.errno != ENOATTR:
                                raise
                        else:
                            raise FUSEError(errno.EEXIST)

                    elif flags & XATTR_REPLACE: # Attribute must exist
                        operations.getxattr(ino, name)

                    operations.setxattr(ino, name, value, ctx)

        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_setxattr(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_getxattr_darwin (fuse_req_t req, fuse_ino_t ino, const_char *cname,
                                size_t size, uint32_t position) with gil:
    cdef int ret

    if position != 0:
        log.error('fuse_getxattr(): non-zero position (%d) not supported' % position)
        ret = fuse_reply_err(req, errno.EIO)
        if ret != 0:
            log.error('fuse_getxattr(): fuse_reply_* failed with %s', strerror(-ret))
    else:
        fuse_getxattr(req, ino, cname, size)

cdef void fuse_getxattr (fuse_req_t req, fuse_ino_t ino, const_char *cname,
                         size_t size) with gil:
    cdef int ret
    cdef ssize_t len_s
    cdef size_t len_
    cdef char *cbuf
    try:
        ctx = get_request_context(req)
        name = PyBytes_FromString(cname)
        with lock:
            buf = operations.getxattr(ino, name, ctx)
        PyBytes_AsStringAndSize(buf, &cbuf, &len_s)
        len_ = <size_t> len_s # guaranteed positive

        if size == 0:
            ret = fuse_reply_xattr(req, len_)
        elif len_ <= size:
            ret = fuse_reply_buf(req, cbuf, len_)
        else:
            ret = fuse_reply_err(req, errno.ERANGE)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_getxattr(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_listxattr (fuse_req_t req, fuse_ino_t ino, size_t size) with gil:
    cdef int ret
    cdef ssize_t len_s
    cdef size_t len_
    cdef char *cbuf
    try:
        ctx = get_request_context(req)
        with lock:
            buf = b'\0'.join(operations.listxattr(ino, ctx)) + b'\0'

        PyBytes_AsStringAndSize(buf, &cbuf, &len_s)
        len_ = <size_t> len_s # guaranteed positive

        if len_ == 1: # No attributes
            len_ = 0

        if size == 0:
            ret = fuse_reply_xattr(req, len_)
        elif len_ <= size:
            ret = fuse_reply_buf(req, cbuf, len_)
        else:
            ret = fuse_reply_err(req, errno.ERANGE)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_listxattr(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_removexattr (fuse_req_t req, fuse_ino_t ino, const_char *cname) with gil:
    cdef int ret
    try:
        ctx = get_request_context(req)
        name = PyBytes_FromString(cname)
        with lock:
            operations.removexattr(ino, name, ctx)
        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_removexattr(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_access (fuse_req_t req, fuse_ino_t ino, int mask) with gil:
    cdef int ret

    try:
        ctx = get_request_context(req)
        with lock:
            allowed = operations.access(ino, mask, ctx)
        if allowed:
            ret = fuse_reply_err(req, 0)
        else:
            ret = fuse_reply_err(req, EPERM)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_access(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_create (fuse_req_t req, fuse_ino_t parent, const_char *cname,
                       mode_t mode, fuse_file_info *fi) with gil:
    cdef int ret
    cdef EntryAttributes entry

    try:
        ctx = get_request_context(req)
        name = PyBytes_FromString(cname)
        with lock:
            tmp = operations.create(parent, name, mode, fi.flags, ctx)
            fi.fh = tmp[0]
            entry = <EntryAttributes?> tmp[1]

        # Cached file data does not need to be invalidated.
        # http://article.gmane.org/gmane.comp.file-systems.fuse.devel/5325/
        fi.keep_cache = 1

        ret = fuse_reply_create(req, &entry.fuse_param, fi)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except:
        ret = handle_exc(req)

    if ret != 0:
        log.error('fuse_create(): fuse_reply_* failed with %s', strerror(-ret))
