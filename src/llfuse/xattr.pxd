'''
xattr.pxd

This file contains Cython definitions for attr/xattr.h

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

cdef extern from "attr/xattr.h":
    int setxattr (char *path, char *name,
                  void *value, int size, int flags) nogil
    
    int getxattr (char *path, char *name,
                  void *value, int size) nogil
