'''
fuse_common.pxd

This file contains Cython definitions for fuse_common.h

Copyright © 2010 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
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
        unsigned proto_major
        unsigned proto_minor
        unsigned max_write
        unsigned max_read
        unsigned max_readahead
        unsigned capable
        unsigned want
        unsigned max_background
        unsigned congestion_threshold
        unsigned time_gran

    struct fuse_session:
        pass

    struct fuse_chan:
        pass

    struct fuse_loop_config:
       int clone_fd
       unsigned max_idle_threads

    # Capability bits for fuse_conn_info.{capable,want}
    enum:
      FUSE_CAP_ASYNC_READ
      FUSE_CAP_POSIX_LOCKS
      FUSE_CAP_ATOMIC_O_TRUNC
      FUSE_CAP_EXPORT_SUPPORT
      FUSE_CAP_DONT_MASK
      FUSE_CAP_SPLICE_WRITE
      FUSE_CAP_SPLICE_MOVE
      FUSE_CAP_SPLICE_READ
      FUSE_CAP_FLOCK_LOCKS
      FUSE_CAP_IOCTL_DIR
      FUSE_CAP_AUTO_INVAL_DATA
      FUSE_CAP_READDIRPLUS
      FUSE_CAP_READDIRPLUS_AUTO
      FUSE_CAP_ASYNC_DIO
      FUSE_CAP_WRITEBACK_CACHE
      FUSE_CAP_NO_OPEN_SUPPORT
      FUSE_CAP_PARALLEL_DIROPS
      FUSE_CAP_POSIX_ACL
      FUSE_CAP_HANDLE_KILLPRIV

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
