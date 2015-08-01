'''
errno.pxd

This file contains Cython definitions for errno.h

Copyright © 2010 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
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
