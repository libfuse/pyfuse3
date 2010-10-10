'''
stat.pxd

This file contains Cython definitions for sys/stat.h

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

cdef extern from "sys/stat.h" nogil:
    ctypedef int dev_t
    ctypedef int ino_t
    ctypedef int mode_t
    ctypedef int nlink_t
    ctypedef int uid_t
    ctypedef int gid_t
    ctypedef int dev_t
    ctypedef int off_t
    ctypedef int blksize_t
    ctypedef int blkcnt_t
    ctypedef struct time_t:
        pass

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

