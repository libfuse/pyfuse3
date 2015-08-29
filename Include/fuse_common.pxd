'''
fuse_common.pxd

This file contains Cython definitions for fuse_common.h

Copyright © 2010 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
'''

from fuse_opt cimport *
from posix.types cimport off_t
from libc.stdint cimport uint64_t

# Based on fuse sources, revision tag fuse_2_9_4
cdef extern from * nogil: # fuse_common.h should not be included

    struct fuse_file_info:
        int flags
        unsigned int direct_io
        unsigned int keep_cache
        unsigned int nonseekable
        uint64_t fh
        uint64_t lock_owner

    struct fuse_conn_info:
        pass

    struct fuse_session:
        pass

    struct fuse_chan:
        pass

    fuse_chan *fuse_mount(char *mountpoint, fuse_args *args)
    void fuse_unmount(char *mountpoint, fuse_chan *ch)
    int fuse_set_signal_handlers(fuse_session *se)
    void fuse_remove_signal_handlers(fuse_session *se)

    # fuse_common.h declares these as enums, but they are
    # actually flags (i.e., FUSE_BUF_IS_FD|FUSE_BUF_FD_SEEK)
    # is a valid variable. Therefore, we declare the type
    # as integer instead.
    ctypedef int fuse_buf_flags
    enum:
        FUSE_BUF_IS_FD
        FUSE_BUF_FD_SEEK
        FUSE_BUF_FD_RETRY

    ctypedef int fuse_buf_copy_flags
    enum:
        FUSE_BUF_NO_SPLICE
        FUSE_BUF_FORCE_SPLICE
        FUSE_BUF_SPLICE_MOVE
        FUSE_BUF_SPLICE_NONBLOCK

    struct fuse_buf:
        size_t size
        fuse_buf_flags flags
        void *mem
        int fd
        off_t pos

    struct fuse_bufvec:
        size_t count
        size_t idx
        size_t off
        fuse_buf buf[1]

    size_t fuse_buf_size(fuse_bufvec *bufv)
    ssize_t fuse_buf_copy(fuse_bufvec *dst, fuse_bufvec *src,
                          fuse_buf_copy_flags flags)
