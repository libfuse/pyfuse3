'''
handlers.pxi

This file defines the FUSE request handlers. It has included
by llfuse.pyx.

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of LLFUSE (http://python-llfuse.googlecode.com).
LLFUSE can be distributed under the terms of the GNU LGPL.
'''

cdef void fuse_init (void *userdata, fuse_conn_info *conn) with gil:
    try:
        with lock:
            operations.init()
    except Exception as e:
        handle_exc('init', e, NULL)
        
cdef void fuse_destroy (void *userdata) with gil:
    # Note: called by fuse_session_destroy()
    try:
        with lock:
            operations.destroy()
    except Exception as e:
        handle_exc('destroy', e, NULL)


    
cdef void fuse_lookup (fuse_req_t req, fuse_ino_t parent,
                       const_char *name) with gil:
    cdef fuse_entry_param entry
    cdef int ret

    try:
        with lock:
            attr = operations.lookup(parent, PyBytes_FromString(name))

        fill_entry_param(attr, &entry)
        
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except Exception as e:
        ret = handle_exc('lookup', e, req)
    else:
        ret = fuse_reply_entry(req, &entry)

    if ret != 0:
        log.error('fuse_lookup(): fuse_reply_* failed with %s',
                  errno.errorcode.get(e.errno, str(e.errno)))
    

cdef void fuse_forget (fuse_req_t req, fuse_ino_t ino,
                       ulong_t nlookup) with gil:
    cdef int ret

    try:
        with lock:
            operations.forget(ino, nlookup)

    except Exception as e:
        handle_exc('forget', e, NULL)

    ret = fuse_reply_none(req)
    if ret != 0:
        log.error('fuse_forget(): fuse_reply_none failed with %s',
                  errno.errorcode.get(e.errno, str(e.errno)))

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
        
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except Exception as e:
        ret = handle_exc('getattr', e, req)
    else:
        ret = fuse_reply_attr(req, &stat, timeout)

    if ret != 0:
        log.error('fuse_getattr(): fuse_reply_* failed with %s',
                  errno.errorcode.get(e.errno, str(e.errno)))

cdef void fuse_setattr (fuse_req_t req, fuse_ino_t ino, c_stat *attr,
                        int to_set, fuse_file_info *fi) with gil:
    cdef c_stat stat
    cdef int ret
    cdef int timeout

    try:
        attr = EntryAttributes()
        
        if to_set & FUSE_SET_ATTR_ATIME:
            attr.st_atime = stat.st_atime + GET_ATIME_NS(stat) * 1e-9

        if to_set & FUSE_SET_ATTR_MTIME:
            attr.st_mtime = stat.st_mtime + GET_MTIME_NS(stat) * 1e-9

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

        fill_c_stat(attr, &stat)
        timeout = attr.attr_timeout
        
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except Exception as e:
        ret = handle_exc('setattr', e, req)
    else:
        ret = fuse_reply_attr(req, &stat, timeout)

    if ret != 0:
        log.error('fuse_setattr(): fuse_reply_* failed with %s',
                  errno.errorcode.get(e.errno, str(e.errno)))

cdef void fuse_readlink (fuse_req_t req, fuse_ino_t ino) with gil:
    cdef int ret
    cdef char* name
    try:
        with lock:
            target = operations.readlink(ino)

        name = PyBytes_AsString(target)
            
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except Exception as e:
        ret = handle_exc('readlink', e, req)
    else:
        ret = fuse_reply_readlink(req, name)

    if ret != 0:
        log.error('fuse_readlink(): fuse_reply_* failed with %s',
                  errno.errorcode.get(e.errno, str(e.errno)))

cdef void fuse_mknod (fuse_req_t req, fuse_ino_t parent, const_char *name,
                      mode_t mode, dev_t rdev) with gil:
    cdef int ret
    cdef fuse_entry_param entry
    cdef fuse_ctx* context
    
    try:
        context = fuse_req_ctx(req)

        ctx = RequestContext()
        ctx.pid = context.pid
        ctx.uid = context.uid
        ctx.gid = context.gid
        ctx.umask = context.umask
        
        with lock:
            attr = operations.mknod(parent, PyBytes_FromString(name), mode,
                                    rdev, ctx)

        fill_entry_param(attr, &entry)
            
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except Exception as e:
        ret = handle_exc('mknod', e, req)
    else:
        ret = fuse_reply_entry(req, &entry)

    if ret != 0:
        log.error('fuse_mknod(): fuse_reply_* failed with %s',
                  errno.errorcode.get(e.errno, str(e.errno)))

cdef void fuse_mkdir (fuse_req_t req, fuse_ino_t parent, const_char *name,
                      mode_t mode) with gil:
    cdef int ret
    cdef fuse_entry_param entry
    cdef fuse_ctx* context
    
    try:
        # Force the entry type to directory
        mode = (mode & ~S_IFMT) | S_IFDIR
        
        context = fuse_req_ctx(req)
        ctx = RequestContext()
        ctx.pid = context.pid
        ctx.uid = context.uid
        ctx.gid = context.gid
        ctx.umask = context.umask
        
        with lock:
            attr = operations.mkdir(parent, PyBytes_FromString(name), mode, ctx)

        fill_entry_param(attr, &entry)
            
    except FUSEError as e:
        ret = fuse_reply_err(req, e.errno)
    except Exception as e:
        ret = handle_exc('mkdir', e, req)
    else:
        ret = fuse_reply_entry(req, &entry)

    if ret != 0:
        log.error('fuse_mkdir(): fuse_reply_* failed with %s',
                  errno.errorcode.get(e.errno, str(e.errno)))

cdef void fuse_unlink (fuse_req_t req, fuse_ino_t parent, const_char *name) with gil:
    pass

cdef void fuse_rmdir (fuse_req_t req, fuse_ino_t parent, const_char *name) with gil:
    pass

cdef void fuse_symlink (fuse_req_t req, const_char *link, fuse_ino_t parent,
                        const_char *name) with gil:
    pass

cdef void fuse_rename (fuse_req_t req, fuse_ino_t parent, const_char *name,
                       fuse_ino_t newparent, const_char *newname) with gil:
    pass

cdef void fuse_link (fuse_req_t req, fuse_ino_t ino, fuse_ino_t newparent,
                     const_char *newname) with gil:
    pass

cdef void fuse_open (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    pass

cdef void fuse_read (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                     fuse_file_info *fi) with gil:
    pass

cdef void fuse_write (fuse_req_t req, fuse_ino_t ino, const_char *buf,
                      size_t size, off_t off, fuse_file_info *fi) with gil:
    pass

cdef void fuse_flush (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    pass

cdef void fuse_release (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    pass

cdef void fuse_fsync (fuse_req_t req, fuse_ino_t ino, int datasync,
                      fuse_file_info *fi) with gil:
    pass

cdef void fuse_opendir (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    pass

cdef void fuse_readdir (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                        fuse_file_info *fi) with gil:
    pass

cdef void fuse_releasedir (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi) with gil:
    pass

cdef void fuse_fsyncdir (fuse_req_t req, fuse_ino_t ino, int datasync,
                         fuse_file_info *fi) with gil:
    pass

cdef void fuse_statfs (fuse_req_t req, fuse_ino_t ino) with gil:
    pass

cdef void fuse_setxattr (fuse_req_t req, fuse_ino_t ino, const_char *name,
                         const_char *value, size_t size, int flags) with gil:
    pass

cdef void fuse_getxattr (fuse_req_t req, fuse_ino_t ino, const_char *name, size_t size) with gil:
    pass

cdef void fuse_listxattr (fuse_req_t req, fuse_ino_t ino, size_t size) with gil:
    pass

cdef void fuse_removexattr (fuse_req_t req, fuse_ino_t ino, const_char *name) with gil:
    pass

cdef void fuse_access (fuse_req_t req, fuse_ino_t ino, int mask) with gil:
    pass

cdef void fuse_create (fuse_req_t req, fuse_ino_t parent, const_char *name,
                       mode_t mode, fuse_file_info *fi) with gil:
    pass
