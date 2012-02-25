'''
xattr.pxd

This file contains Cython definitions for attr/xattr.h

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

IF UNAME_SYSNAME == "Darwin":
    cdef extern from "sys/xattr.h" nogil:
        int c_setxattr "setxattr" (char *path, char *name,
                                   void *value, int size,
                                   int flags, int options)
        
        int c_getxattr "getxattr" (char *path, char *name,
                                   void *value, int size,
                                   int position, int options)

        int XATTR_CREATE
        int XATTR_REPLACE
        int XATTR_NOFOLLOW
        int XATTR_NOSECURITY
        int XATTR_NODEFAULT

    cdef inline int setxattr (char *path, char *name,
                              void *value, int size, int flags) nogil:
        return c_setxattr(path, name, value, size, flags, 0)
    
    cdef inline int getxattr (char *path, char *name,
                              void *value, int size) nogil:
        return c_getxattr(path, name, value, size, 0, 0)

ELSE:
    cdef extern from "attr/xattr.h" nogil:
        int setxattr (char *path, char *name,
                      void *value, int size, int flags)
        
        int getxattr (char *path, char *name,
                      void *value, int size)

        int XATTR_CREATE
        int XATTR_REPLACE
