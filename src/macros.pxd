'''
macros.pxd

Cython definitions for macros.c

Copyright © 2018 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

from posix.stat cimport struct_stat

cdef extern from "macros.c" nogil:
    long GET_BIRTHTIME(struct_stat* buf)
    long GET_ATIME_NS(struct_stat* buf)
    long GET_CTIME_NS(struct_stat* buf)
    long GET_MTIME_NS(struct_stat* buf)
    long GET_BIRTHTIME_NS(struct_stat* buf)

    void SET_BIRTHTIME(struct_stat* buf, long val)
    void SET_ATIME_NS(struct_stat* buf, long val)
    void SET_CTIME_NS(struct_stat* buf, long val)
    void SET_MTIME_NS(struct_stat* buf, long val)
    void SET_BIRTHTIME_NS(struct_stat* buf, long val)

    void ASSIGN_DARWIN(void*, void*)
    void ASSIGN_NOT_DARWIN(void*, void*)
