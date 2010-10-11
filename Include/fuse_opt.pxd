'''
fuse_opt.pxd

This file contains Cython definitions for fuse_opt.h

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''


# Based on fuse sources, revision tag fuse_2_8_3
cdef extern from "fuse_opt.h" nogil:
    struct fuse_args:
        int argc
        char **argv
        int allocated
