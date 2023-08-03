'''
fuse_lowlevel.pxd

This file contains Cython definitions for fuse_lowlevel.h

Copyright © 2010 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

from fuse_common cimport *
from posix.stat cimport *
from posix.types cimport *
from libc_extra cimport statvfs
from libc.stdlib cimport const_char
from libc.stdint cimport uint32_t

# Based on fuse sources, revision tag fuse-3.2.6
cdef extern from "<fuse_lowlevel.h>" nogil:
    enum:
      FUSE_ROOT_ID

    ctypedef unsigned fuse_ino_t
    ctypedef struct fuse_req:
        pass
    ctypedef fuse_req* fuse_req_t

    struct fuse_entry_param:
        fuse_ino_t ino
        uint64_t generation
        struct_stat attr
        double attr_timeout
        double entry_timeout

    struct fuse_ctx:
        uid_t uid
        gid_t gid
        pid_t pid
        mode_t umask

    struct fuse_forget_data:
        fuse_ino_t ino
        uint64_t nlookup

    ctypedef fuse_ctx const_fuse_ctx "const struct fuse_ctx"
    int FUSE_SET_ATTR_MODE
    int FUSE_SET_ATTR_UID
    int FUSE_SET_ATTR_GID
    int FUSE_SET_ATTR_SIZE
    int FUSE_SET_ATTR_ATIME
    int FUSE_SET_ATTR_MTIME
    int FUSE_SET_ATTR_ATIME_NOW
    int FUSE_SET_ATTR_MTIME_NOW
    int FUSE_SET_ATTR_CTIME

    # Request handlers
    # We allow these functions to raise exceptions because we will catch them
    # when checking exception status on return from fuse_session_process_buf().
    struct fuse_lowlevel_ops:
        void (*init) (void *userdata, fuse_conn_info *conn) except *
        void (*destroy) (void *userdata) except *
        void (*lookup) (fuse_req_t req, fuse_ino_t parent, const_char *name) except *
        void (*forget) (fuse_req_t req, fuse_ino_t ino, uint64_t nlookup) except *
        void (*getattr) (fuse_req_t req, fuse_ino_t ino,
                         fuse_file_info *fi) except *
        void (*setattr) (fuse_req_t req, fuse_ino_t ino, struct_stat *attr,
                         int to_set, fuse_file_info *fi) except *
        void (*readlink) (fuse_req_t req, fuse_ino_t ino) except *
        void (*mknod) (fuse_req_t req, fuse_ino_t parent, const_char *name,
                       mode_t mode, dev_t rdev) except *
        void (*mkdir) (fuse_req_t req, fuse_ino_t parent, const_char *name,
                       mode_t mode) except *
        void (*unlink) (fuse_req_t req, fuse_ino_t parent, const_char *name) except *
        void (*rmdir) (fuse_req_t req, fuse_ino_t parent, const_char *name) except *
        void (*symlink) (fuse_req_t req, const_char *link, fuse_ino_t parent,
                         const_char *name) except *
        void (*rename) (fuse_req_t req, fuse_ino_t parent, const_char *name,
                        fuse_ino_t newparent, const_char *newname, unsigned flags) except *
        void (*link) (fuse_req_t req, fuse_ino_t ino, fuse_ino_t newparent,
                      const_char *newname) except *
        void (*open) (fuse_req_t req, fuse_ino_t ino,
                      fuse_file_info *fi) except *
        void (*read) (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                      fuse_file_info *fi) except *
        void (*write) (fuse_req_t req, fuse_ino_t ino, const_char *buf,
                       size_t size, off_t off, fuse_file_info *fi) except *
        void (*flush) (fuse_req_t req, fuse_ino_t ino,
                       fuse_file_info *fi) except *
        void (*release) (fuse_req_t req, fuse_ino_t ino,
                         fuse_file_info *fi) except *
        void (*fsync) (fuse_req_t req, fuse_ino_t ino, int datasync,
                       fuse_file_info *fi) except *
        void (*opendir) (fuse_req_t req, fuse_ino_t ino,
                         fuse_file_info *fi) except *
        void (*readdir) (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                         fuse_file_info *fi) except *
        void (*releasedir) (fuse_req_t req, fuse_ino_t ino,
                            fuse_file_info *fi) except *
        void (*fsyncdir) (fuse_req_t req, fuse_ino_t ino, int datasync,
                          fuse_file_info *fi) except *
        void (*statfs) (fuse_req_t req, fuse_ino_t ino) except *
        void (*setxattr) (fuse_req_t req, fuse_ino_t ino, const_char *name,
                          const_char *value, size_t size, int flags) except *
        void (*getxattr) (fuse_req_t req, fuse_ino_t ino, const_char *name,
                          size_t size) except *
        void (*listxattr) (fuse_req_t req, fuse_ino_t ino, size_t size) except *
        void (*removexattr) (fuse_req_t req, fuse_ino_t ino, const_char *name) except *
        void (*access) (fuse_req_t req, fuse_ino_t ino, int mask) except *
        void (*create) (fuse_req_t req, fuse_ino_t parent, const_char *name,
                        mode_t mode, fuse_file_info *fi) except *
        void (*write_buf) (fuse_req_t req, fuse_ino_t ino, fuse_bufvec *bufv,
                           off_t off, fuse_file_info *fi) except *
        void (*retrieve_reply) (fuse_req_t req, void *cookie, fuse_ino_t ino,
                                off_t offset, fuse_bufvec *bufv) except *
        void (*forget_multi) (fuse_req_t req, size_t count,
                              fuse_forget_data *forgets) except *
        void (*fallocate) (fuse_req_t req, fuse_ino_t ino, int mode,
                           off_t offset, off_t length, fuse_file_info *fi) except *
        void (*readdirplus) (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                             fuse_file_info *fi) except *


    # Reply functions
    int fuse_reply_err(fuse_req_t req, int err)
    void fuse_reply_none(fuse_req_t req)
    int fuse_reply_entry(fuse_req_t req, fuse_entry_param *e)
    int fuse_reply_create(fuse_req_t req, fuse_entry_param *e,
                          fuse_file_info *fi)
    int fuse_reply_attr(fuse_req_t req, struct_stat *attr,
                        double attr_timeout)
    int fuse_reply_readlink(fuse_req_t req, const_char *link)
    int fuse_reply_open(fuse_req_t req, fuse_file_info *fi)
    int fuse_reply_write(fuse_req_t req, size_t count)
    int fuse_reply_buf(fuse_req_t req, const_char *buf, size_t size)
    int fuse_reply_data(fuse_req_t req, fuse_bufvec *bufv,
                        fuse_buf_copy_flags flags)
    int fuse_reply_statfs(fuse_req_t req, statvfs *stbuf)
    int fuse_reply_xattr(fuse_req_t req, size_t count)

    size_t fuse_add_direntry(fuse_req_t req, const_char *buf, size_t bufsize,
                             const_char *name, struct_stat *stbuf,
                             off_t off)
    size_t fuse_add_direntry_plus(fuse_req_t req, char *buf, size_t bufsize,
                              char *name, fuse_entry_param *e, off_t off)

    # Notification
    int fuse_lowlevel_notify_inval_inode(fuse_session *se, fuse_ino_t ino,
                                         off_t off, off_t len)
    int fuse_lowlevel_notify_inval_entry(fuse_session *se, fuse_ino_t parent,
                                         const_char *name, size_t namelen)
    int fuse_lowlevel_notify_delete(fuse_session *se, fuse_ino_t parent,
                                    fuse_ino_t child, const_char *name,
                                    size_t namelen)
    int fuse_lowlevel_notify_store(fuse_session *se, fuse_ino_t ino,
                                   off_t offset, fuse_bufvec *bufv,
                                   fuse_buf_copy_flags flags)
    int fuse_lowlevel_notify_retrieve(fuse_session *se, fuse_ino_t ino,
                                      size_t size, off_t offset, void *cookie)

    # Utility functions
    void *fuse_req_userdata(fuse_req_t req)
    fuse_ctx *fuse_req_ctx(fuse_req_t req)
    int fuse_req_getgroups(fuse_req_t req, size_t size, gid_t list[])


    # Inquiry functions
    void fuse_lowlevel_version()
    void fuse_lowlevel_help()

    # Filesystem setup & teardown
    fuse_session *fuse_session_new(fuse_args *args, fuse_lowlevel_ops *op,
                                   size_t op_size, void *userdata)
    int fuse_session_mount(fuse_session *se, char *mountpoint)
    int fuse_session_loop(fuse_session *se)
    int fuse_session_loop_mt(fuse_session *se, fuse_loop_config *config);
    void fuse_session_exit(fuse_session *se)
    void fuse_session_reset(fuse_session *se)
    bint fuse_session_exited(fuse_session *se)
    void fuse_session_unmount(fuse_session *se)
    void fuse_session_destroy(fuse_session *se)

    # Custom event loop support
    int fuse_session_fd(fuse_session *se)
    int fuse_session_receive_buf(fuse_session *se, fuse_buf *buf)
    void fuse_session_process_buf(fuse_session *se, fuse_buf *buf) except *
