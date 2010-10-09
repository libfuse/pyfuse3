'''
types.pxd

This file contains Cython definitions for sys/types.h.

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

from dirent cimport *

cdef extern from "sys/types.h":
    DIR *opendir(char *name) nogil
    int closedir(DIR* dirp) nogil

    
