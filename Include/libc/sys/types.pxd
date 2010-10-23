'''
types.pxd

This file contains Cython definitions for sys/types.h

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

cdef extern from "sys/types.h" nogil:
    ctypedef int pid_t
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
    ctypedef int time_t
