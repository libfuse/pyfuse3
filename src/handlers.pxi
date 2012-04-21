'''
handlers.pxi

This file defines the FUSE request handlers. It is included
by llfuse.pyx.

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of LLFUSE (http://python-llfuse.googlecode.com).
LLFUSE can be distributed under the terms of the GNU LGPL.
'''

cdef void fuse_init (void *userdata, fuse_conn_info *conn) with gil:
    try:
        with lock:
            operations.init()
    except BaseException as e:
        handle_exc('init', e, NULL)
        
cdef void fuse_destroy (void *userdata) with gil:
    # Note: called by fuse_session_destroy(), i.e. not as part of the
    # main loop but only when llfuse.close() is called.
    # (therefore we don't obtain the global lock)
    global exc_info
    try:
        operations.destroy()
    except:
        if not exc_info:
            exc_info = sys.exc_info()
        else:
            log.exception('Exception after kill:')
    
cdef void fuse_lookup (fuse_req_t req, fuse_ino_t parent,
                       const_char *name) with gil:
    cdef fuse_entry_param entry
    cdef int ret

    try:
        with lock:
            attr = operations.lookup(parent, PyBytes_FromString(name))
        fill_entry_param(attr, &entry)
        ret = fuse_reply_entry(req, &entry)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('lookup', e, req)

    if ret != 0:
        log.error('fuse_lookup(): fuse_reply_* failed with %s', strerror(-ret))
    

cdef void fuse_forget (fuse_req_t req, fuse_ino_t ino,
                       ulong_t nlookup) with gil:
    try:
        with lock:
            operations.forget([(ino, nlookup)])
    except BaseException as e:
        handle_exc('forget', e, NULL)
    fuse_reply_none(req)

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
        ret = fuse_reply_attr(req, &stat, timeout)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('getattr', e, req)

    if ret != 0:
        log.error('fuse_getattr(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_setattr (fuse_req_t req, fuse_ino_t ino, c_stat *stat,
                        int to_set, fuse_file_info *fi) with gil:
    cdef int ret
    cdef c_stat stat_n
    cdef int timeout

    try:
        attr = EntryAttributes()
        
        # Type casting required on 64bit, where double
        # is smaller than long int.
        if to_set & FUSE_SET_ATTR_ATIME:
            attr.st_atime = <double> stat.st_atime + <double> GET_ATIME_NS(stat) * 1e-9

        if to_set & FUSE_SET_ATTR_MTIME:
            attr.st_mtime = <double> stat.st_mtime + <double> GET_MTIME_NS(stat) * 1e-9

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

        fill_c_stat(attr, &stat_n)
        timeout = attr.attr_timeout
        ret = fuse_reply_attr(req, &stat_n, timeout)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('setattr', e, req)

    if ret != 0:
        log.error('fuse_setattr(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_readlink (fuse_req_t req, fuse_ino_t ino) with gil:
    cdef int ret
    cdef char* name
    try:
        with lock:
            target = operations.readlink(ino)
        name = PyBytes_AsString(target)
        ret = fuse_reply_readlink(req, name)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('readlink', e, req)

    if ret != 0:
        log.error('fuse_readlink(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_mknod (fuse_req_t req, fuse_ino_t parent, const_char *name,
                      mode_t mode, dev_t rdev) with gil:
    cdef int ret
    cdef fuse_entry_param entry
    
    try:
        ctx = get_request_context(req)
        with lock:
            attr = operations.mknod(parent, PyBytes_FromString(name), mode,
                                    rdev, ctx)
        fill_entry_param(attr, &entry)
        ret = fuse_reply_entry(req, &entry)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('mknod', e, req)

    if ret != 0:
        log.error('fuse_mknod(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_mkdir (fuse_req_t req, fuse_ino_t parent, const_char *name,
                      mode_t mode) with gil:
    cdef int ret
    cdef fuse_entry_param entry
    
    try:
        # Force the entry type to directory. We need to explicitly cast,
        # because on BSD the S_* are not of type mode_t.
        mode = <mode_t> ((mode & ~S_IFMT) | S_IFDIR)
        ctx = get_request_context(req)
        with lock:
            attr = operations.mkdir(parent, PyBytes_FromString(name), mode, ctx)
        fill_entry_param(attr, &entry)
        ret = fuse_reply_entry(req, &entry)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('mkdir', e, req)

    if ret != 0:
        log.error('fuse_mkdir(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_unlink (fuse_req_t req, fuse_ino_t parent, const_char *name) with gil:
    cdef int ret
    
    try:
        with lock:
            operations.unlink(parent, PyBytes_FromString(name))
        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('unlink', e, req)

    if ret != 0:
        log.error('fuse_unlink(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_rmdir (fuse_req_t req, fuse_ino_t parent, const_char *name) with gil:
    cdef int ret
    
    try:
        with lock:
            operations.rmdir(parent, PyBytes_FromString(name))
        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('rmdir', e, req)

    if ret != 0:
        log.error('fuse_rmdir(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_symlink (fuse_req_t req, const_char *link, fuse_ino_t parent,
                        const_char *name) with gil:
    cdef int ret
    cdef fuse_entry_param entry
    
    try:
        ctx = get_request_context(req)
        with lock:
            attr = operations.symlink(parent, PyBytes_FromString(name),
                                      PyBytes_FromString(link), ctx)
        fill_entry_param(attr, &entry)
        ret = fuse_reply_entry(req, &entry)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('symlink', e, req)

    if ret != 0:
        log.error('fuse_symlink(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_rename (fuse_req_t req, fuse_ino_t parent, const_char *name,
                       fuse_ino_t newparent, const_char *newname) with gil:
    cdef int ret
    
    try:
        with lock:
            operations.rename(parent, PyBytes_FromString(name),
                              newparent, PyBytes_FromString(newname))
        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('rename', e, req)

    if ret != 0:
        log.error('fuse_rename(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_link (fuse_req_t req, fuse_ino_t ino, fuse_ino_t newparent,
                     const_char *newname) with gil:
    cdef int ret
    cdef fuse_entry_param entry
    
    try:
        with lock:
            attr = operations.link(ino, newparent, PyBytes_FromString(newname))
        fill_entry_param(attr, &entry)
        ret = fuse_reply_entry(req, &entry)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('link', e, req)

    if ret != 0:
        log.error('fuse_link(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_open (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    cdef int ret
    
    try:
        with lock:
            fi.fh = operations.open(ino, fi.flags) 

        # Cached file data does not need to be invalidated.
        # http://article.gmane.org/gmane.comp.file-systems.fuse.devel/5325/
        fi.keep_cache = 1
        
        ret = fuse_reply_open(req, fi)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('open', e, req)

    if ret != 0:
        log.error('fuse_link(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_read (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                     fuse_file_info *fi) with gil:
    cdef int ret
    cdef ssize_t len_
    cdef char* cbuf
    
    try:
        with lock:
            buf = operations.read(fi.fh, off, size) 
        PyBytes_AsStringAndSize(buf, &cbuf, &len_)
        ret = fuse_reply_buf(req, cbuf, len_)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('read', e, req)

    if ret != 0:
        log.error('fuse_read(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_write (fuse_req_t req, fuse_ino_t ino, const_char *buf,
                      size_t size, off_t off, fuse_file_info *fi) with gil:
    cdef int ret
    cdef size_t len_

    # GCC thinks this may end up uninitialized
    len_ = 0
    
    try:
        pbuf = PyBytes_FromStringAndSize(buf, size)
        with lock:
            len_ = operations.write(fi.fh, off, pbuf)
        ret = fuse_reply_write(req, len_)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('write', e, req)

    if ret != 0:
        log.error('fuse_write(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_flush (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    cdef int ret
    
    try:
        with lock:
            operations.flush(fi.fh)
        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('flush', e, req)

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
    except BaseException as e:
        ret = handle_exc('release', e, req)

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
    except BaseException as e:
        ret = handle_exc('fsync', e, req)

    if ret != 0:
        log.error('fuse_fsync(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_opendir (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    cdef int ret
    
    try:
        with lock:
            fi.fh = operations.opendir(ino) 

        ret = fuse_reply_open(req, fi)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('opendir', e, req)

    if ret != 0:
        log.error('fuse_opendir(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_readdir (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                        fuse_file_info *fi) with gil:
    cdef int ret
    cdef char *cname, *buf
    cdef size_t len_, acc_size
    cdef c_stat stat

    # GCC thinks this may end up uninitialized
    ret = 0
    
    try:
        acc_size = 0
        buf = NULL
        with lock:
            for (name, attr, next_) in operations.readdir(fi.fh, off):
                if buf == NULL:
                    buf = <char*> stdlib.malloc(size * sizeof(char))
                cname = PyBytes_AsString(name)
                fill_c_stat(attr, &stat)
                len_ = fuse_add_direntry(req, buf + acc_size, size - acc_size,
                                         cname, &stat, next_)
                if len_ > (size - acc_size):
                    break
                acc_size += len_
        ret = fuse_reply_buf(req, buf, acc_size)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('readdir', e, req)
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
    except BaseException as e:
        ret = handle_exc('releasedir', e, req)

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
    except BaseException as e:
        ret = handle_exc('fsyncdir', e, req)

    if ret != 0:
        log.error('fuse_fsyncdir(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_statfs (fuse_req_t req, fuse_ino_t ino) with gil:
    cdef int ret
    cdef statvfs cstats

    # We don't set all the components
    string.memset(&cstats, 0, sizeof(cstats))
    try:
        with lock:
            stats = operations.statfs()

        fill_statvfs(stats, &cstats)
        ret = fuse_reply_statfs(req, &cstats)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('statfs', e, req)

    if ret != 0:
        log.error('fuse_statfs(): fuse_reply_* failed with %s', strerror(-ret))

IF UNAME_SYSNAME == "Darwin":
    cdef void fuse_setxattr_darwin (fuse_req_t req, fuse_ino_t ino, const_char *cname,
                                    const_char *cvalue, size_t size, int flags,
                                    uint32_t position) with gil:
        cdef int ret

        if position != 0:
            log.error('fuse_setxattr(): non-zero position (%d) not supported', position)
            ret = fuse_reply_err(req, errno.EIO)
            if ret != 0:
                log.error('fuse_setxattr(): fuse_reply_err failed with %s', strerror(-ret))
        else:
            fuse_setxattr(req, ino, cname, cvalue, size, flags)

cdef void fuse_setxattr (fuse_req_t req, fuse_ino_t ino, const_char *cname,
                         const_char *cvalue, size_t size, int flags) with gil:
    cdef int ret
    
    try:
        name = PyBytes_FromString(cname)
        value = PyBytes_FromStringAndSize(cvalue, size)

        # Special case for deadlock debugging
        if ino == FUSE_ROOT_ID and string.strcmp(cname, 'fuse_stacktrace') == 0:
            operations.stacktrace()
        else:
            # Make sure we know all the flags
            if flags & ~(xattr.XATTR_CREATE | xattr.XATTR_REPLACE):
                raise ValueError('unknown flag(s): %o' % flags)

            with lock:
                if flags & xattr.XATTR_CREATE: # Attribute must not exist
                    try:
                        operations.getxattr(ino, name)
                    except FUSEError as e:
                        if e.errno == errno.ENOATTR:
                            pass
                        raise
                    else:
                        raise FUSEError(errno.EEXIST)
                
                elif flags & xattr.XATTR_REPLACE: # Attribute must exist
                    operations.getxattr(ino, name)
                    
                operations.setxattr(ino, name, value)
                
        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('setxattr', e, req)

    if ret != 0:
        log.error('fuse_setxattr(): fuse_reply_* failed with %s', strerror(-ret))

IF UNAME_SYSNAME == "Darwin":
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
    cdef ssize_t len_
    cdef char *cbuf
    try:
        name = PyBytes_FromString(cname)
        with lock:
            buf = operations.getxattr(ino, name)
        PyBytes_AsStringAndSize(buf, &cbuf, &len_)

        if size == 0:
            ret = fuse_reply_xattr(req, len_)
        elif <size_t> len_ <= size:
            ret = fuse_reply_buf(req, cbuf, len_)
        else:
            ret = fuse_reply_err(req, errno.ERANGE)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('getxattr', e, req)

    if ret != 0:
        log.error('fuse_getxattr(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_listxattr (fuse_req_t req, fuse_ino_t ino, size_t size) with gil:
    cdef int ret
    cdef ssize_t len_
    cdef char *cbuf
    try:
        with lock:
            buf = b'\0'.join(operations.listxattr(ino)) + b'\0'

        PyBytes_AsStringAndSize(buf, &cbuf, &len_)
        
        if len_ == 1: # No attributes
            len_ = 0

        if size == 0:
            ret = fuse_reply_xattr(req, len_)
        elif <size_t> len_ <= size:
            ret = fuse_reply_buf(req, cbuf, len_)
        else:
            ret = fuse_reply_err(req, errno.ERANGE)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('listxattr', e, req)

    if ret != 0:
        log.error('fuse_listxattr(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_removexattr (fuse_req_t req, fuse_ino_t ino, const_char *cname) with gil:
    cdef int ret
    try:
        name = PyBytes_FromString(cname)
        with lock:
            operations.removexattr(ino, name)
        ret = fuse_reply_err(req, 0)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('removexattr', e, req)

    if ret != 0:
        log.error('fuse_removexattr(): fuse_reply_* failed with %s', strerror(-ret))

cdef void fuse_access (fuse_req_t req, fuse_ino_t ino, int mask) with gil:
    cdef int ret
    cdef fuse_entry_param entry
    
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
    except BaseException as e:
        ret = handle_exc('access', e, req)

    if ret != 0:
        log.error('fuse_access(): fuse_reply_* failed with %s', strerror(-ret))


cdef void fuse_create (fuse_req_t req, fuse_ino_t parent, const_char *cname,
                       mode_t mode, fuse_file_info *fi) with gil:
    cdef int ret
    cdef fuse_entry_param entry
    
    try:
        ctx = get_request_context(req)
        name = PyBytes_FromString(cname)
        with lock:
            (fi.fh, attr) = operations.create(parent, name, mode, fi.flags, ctx)

        # Cached file data does not need to be invalidated.
        # http://article.gmane.org/gmane.comp.file-systems.fuse.devel/5325/
        fi.keep_cache = 1
        
        fill_entry_param(attr, &entry)
        ret = fuse_reply_create(req, &entry, fi)
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except BaseException as e:
        ret = handle_exc('create', e, req)

    if ret != 0:
        log.error('fuse_create(): fuse_reply_* failed with %s', strerror(-ret))
