'''
stat.pxd

This file contains Cython definitions for sys/stat.h

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

from libc.sys.types cimport *

cdef extern from "sys/stat.h" nogil:
    enum st_mode_constants:
        S_IFMT
        S_IFDIR

    struct stat:
        dev_t     st_dev
        ino_t     st_ino
        mode_t    st_mode
        nlink_t   st_nlink
        uid_t     st_uid
        gid_t     st_gid
        dev_t     st_rdev
        off_t     st_size
        blksize_t st_blksize
        blkcnt_t  st_blocks
        time_t    st_atime
        time_t    st_mtime
        time_t    st_ctime

