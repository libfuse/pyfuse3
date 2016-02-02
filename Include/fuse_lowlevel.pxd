'''
fuse_lowlevel.pxd

This file contains Cython definitions for fuse_lowlevel.h

Copyright © 2010 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
'''

from fuse_common cimport *
from posix.stat cimport *
from posix.types cimport *
from libc.sys.statvfs cimport *
from libc.stdlib cimport const_char
from libc.stdint cimport uint32_t

# Based on fuse sources, revision tag fuse_2_9_4
cdef extern from "<fuse_lowlevel.h>" nogil:
    int FUSE_ROOT_ID

    ctypedef int fuse_ino_t
    ctypedef struct fuse_req:
        pass
    ctypedef fuse_req* fuse_req_t

    ctypedef int ulong_t "unsigned long"

    struct fuse_entry_param:
        fuse_ino_t ino
        unsigned long generation
        struct_stat attr
        double attr_timeout
        double entry_timeout

    struct fuse_ctx:
        uid_t uid
        gid_t gid
        pid_t pid
        mode_t umask

    struct fuse_forget_data:
        uint64_t ino
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

    struct fuse_lowlevel_ops:
        void (*init) (void *userdata, fuse_conn_info *conn)
        void (*destroy) (void *userdata)
        void (*lookup) (fuse_req_t req, fuse_ino_t parent, const_char *name)
        void (*forget) (fuse_req_t req, fuse_ino_t ino, ulong_t nlookup)
        void (*getattr) (fuse_req_t req, fuse_ino_t ino,
                         fuse_file_info *fi)
        void (*setattr) (fuse_req_t req, fuse_ino_t ino, struct_stat *attr,
                         int to_set, fuse_file_info *fi)
        void (*readlink) (fuse_req_t req, fuse_ino_t ino)
        void (*mknod) (fuse_req_t req, fuse_ino_t parent, const_char *name,
                       mode_t mode, dev_t rdev)
        void (*mkdir) (fuse_req_t req, fuse_ino_t parent, const_char *name,
                       mode_t mode)
        void (*unlink) (fuse_req_t req, fuse_ino_t parent, const_char *name)
        void (*rmdir) (fuse_req_t req, fuse_ino_t parent, const_char *name)
        void (*symlink) (fuse_req_t req, const_char *link, fuse_ino_t parent,
                         const_char *name)
        void (*rename) (fuse_req_t req, fuse_ino_t parent, const_char *name,
                        fuse_ino_t newparent, const_char *newname)
        void (*link) (fuse_req_t req, fuse_ino_t ino, fuse_ino_t newparent,
                      const_char *newname)
        void (*open) (fuse_req_t req, fuse_ino_t ino,
                      fuse_file_info *fi)
        void (*read) (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                      fuse_file_info *fi)
        void (*write) (fuse_req_t req, fuse_ino_t ino, const_char *buf,
                       size_t size, off_t off, fuse_file_info *fi)
        void (*flush) (fuse_req_t req, fuse_ino_t ino,
                       fuse_file_info *fi)
        void (*release) (fuse_req_t req, fuse_ino_t ino,
                         fuse_file_info *fi)
        void (*fsync) (fuse_req_t req, fuse_ino_t ino, int datasync,
                       fuse_file_info *fi)
        void (*opendir) (fuse_req_t req, fuse_ino_t ino,
                         fuse_file_info *fi)
        void (*readdir) (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                         fuse_file_info *fi)
        void (*releasedir) (fuse_req_t req, fuse_ino_t ino,
                            fuse_file_info *fi)
        void (*fsyncdir) (fuse_req_t req, fuse_ino_t ino, int datasync,
                          fuse_file_info *fi)
        void (*statfs) (fuse_req_t req, fuse_ino_t ino)
        void (*setxattr) (fuse_req_t req, fuse_ino_t ino, const_char *name,
                          const_char *value, size_t size, int flags)
        void (*getxattr) (fuse_req_t req, fuse_ino_t ino, const_char *name,
                          size_t size)
        void (*listxattr) (fuse_req_t req, fuse_ino_t ino, size_t size)
        void (*removexattr) (fuse_req_t req, fuse_ino_t ino, const_char *name)
        void (*access) (fuse_req_t req, fuse_ino_t ino, int mask)
        void (*create) (fuse_req_t req, fuse_ino_t parent, const_char *name,
                        mode_t mode, fuse_file_info *fi)
        void (*write_buf) (fuse_req_t req, fuse_ino_t ino, fuse_bufvec *bufv,
                           off_t off, fuse_file_info *fi)
        void (*retrieve_reply) (fuse_req_t req, void *cookie, fuse_ino_t ino,
                                off_t offset, fuse_bufvec *bufv)
        void (*forget_multi) (fuse_req_t req, size_t count,
                              fuse_forget_data *forgets)
        void (*fallocate) (fuse_req_t req, fuse_ino_t ino, int mode,
                           off_t offset, off_t length, fuse_file_info *fi)

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

    int fuse_lowlevel_notify_inval_inode(fuse_chan *ch, fuse_ino_t ino,
                                         off_t off, off_t len)
    int fuse_lowlevel_notify_inval_entry(fuse_chan *ch, fuse_ino_t parent,
                                         const_char *name, size_t namelen)
    int fuse_lowlevel_notify_delete(fuse_chan *ch, fuse_ino_t parent,
                                    fuse_ino_t child, const_char *name,
                                    size_t namelen)
    int fuse_lowlevel_notify_store(fuse_chan *ch, fuse_ino_t ino,
                                   off_t offset, fuse_bufvec *bufv,
                                   fuse_buf_copy_flags flags)
    int fuse_lowlevel_notify_retrieve(fuse_chan *ch, fuse_ino_t ino,
                                      size_t size, off_t offset, void *cookie);

    void *fuse_req_userdata(fuse_req_t req)
    fuse_ctx *fuse_req_ctx(fuse_req_t req)
    int fuse_req_getgroups(fuse_req_t req, size_t size, gid_t list[])
    fuse_session *fuse_lowlevel_new(fuse_args *args,
                                    fuse_lowlevel_ops *op,
                                    size_t op_size, void *userdata)


    struct fuse_session_ops:
        pass

    fuse_session *fuse_session_new(fuse_session_ops *op, void *data)
    void fuse_session_add_chan(fuse_session *se, fuse_chan *ch)
    int fuse_session_receive_buf(fuse_session *se, fuse_buf *buf,
                                 fuse_chan **chp)
    void fuse_session_process_buf(fuse_session *se,
                                  fuse_buf *buf, fuse_chan *ch)
    void fuse_session_remove_chan(fuse_chan *ch)
    void fuse_session_reset(fuse_session *se)
    void fuse_session_exit(fuse_session *se)
    void fuse_session_destroy(fuse_session *se)
    int fuse_session_loop(fuse_session *se)
    int fuse_session_loop_mt(fuse_session *se)
    void fuse_chan_destroy(fuse_chan *ch)
    size_t fuse_chan_bufsize(fuse_chan *ch)
    int fuse_session_exited(fuse_session *se)
