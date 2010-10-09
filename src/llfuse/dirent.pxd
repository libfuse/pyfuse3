'''
dirent.pxd

This file contains Cython definitions for dirent.h.

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

cdef extern from "dirent.h":
    ctypedef struct DIR:
        pass
    cdef struct dirent:
        char* d_name
        
    dirent* readdir(DIR* dirp) nogil
    int readdir_r(DIR *dirp, dirent *entry, dirent **result) nogil
