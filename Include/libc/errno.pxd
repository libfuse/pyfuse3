'''
errno.pxd

This file contains Cython definitions for errno.h

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

cdef extern from "errno.h" nogil:

    enum: EDOM
    enum: EILSEQ
    enum: ERANGE
    enum: ENOATTR
    enum: ENOSYS
    enum: ENOENT
    enum: EEXIST
    enum: EIO

    int errno
