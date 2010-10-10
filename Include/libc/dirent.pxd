'''
dirent.pxd

This file contains Cython definitions for dirent.h and sys/types.h

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

cdef extern from "dirent.h" nogil:
    ctypedef struct DIR:
        pass
    cdef struct dirent:
        char* d_name
        
    dirent* readdir(DIR* dirp)
    int readdir_r(DIR *dirp, dirent *entry, dirent **result)

cdef extern from "sys/types.h" nogil:
    DIR *opendir(char *name)
    int closedir(DIR* dirp)
