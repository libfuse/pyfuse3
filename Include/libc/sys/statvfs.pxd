'''
statvfs.pxd

This file contains Cython definitions for sys/statvfs.h

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

cdef extern from "sys/statvfs.h" nogil:
    ctypedef int fsblkcnt_t
    ctypedef int fsfilcnt_t
    
    struct statvfs: 
        int f_bsize
        int f_frsize
        fsblkcnt_t     f_blocks
        fsblkcnt_t     f_bfree
        fsblkcnt_t     f_bavail
        fsfilcnt_t     f_files
        fsfilcnt_t     f_ffree
        fsfilcnt_t     f_favail

