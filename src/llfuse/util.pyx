'''
util.pyx

This Cython source file is compiled into the llfuse.utils module. It
contains FUSE bindings for some libc functions that are not exposed by
Python itself.

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

import os
cimport xattr
cimport python_exc

from errno cimport *
from dirent cimport *
from types cimport *
from string cimport *
from python_string cimport PyString_AsStringAndSize, PyString_FromStringAndSize
from stdlib cimport malloc, free

def listdir(path):
    '''Like os.listdir(), but releases the GIL'''
    
    cdef DIR* dirp
    cdef dirent ent
    cdef dirent* res
    cdef int ret
    global errno

    with nogil:
        dirp = opendir(path)
    names = list()

    while True:
        errno = 0
        with nogil:
            ret = readdir_r(dirp, &ent, &res)
        if ret != 0:
            raise OSError(errno, os.strerror(errno), path)
        if res is NULL:
            break
        if strcmp(ent.d_name, b'.') == 0 or strcmp(ent.d_name, b'..') == 0:
            continue

        names.append(ent.d_name)
        
    with nogil:
        closedir(dirp)
    
    return names


def setxattr(path, name, value):
    '''Set extended attribute'''

    cdef int ret
    cdef Py_ssize_t n
    cdef char* s

    ret = PyString_AsStringAndSize(value, &s, &n)
    if ret != 0:
        # TODO: Need to re-raise exception somehow
        return NULL

    with nogil:
        ret = xattr.setxattr(path, name, s, n, 0)

    if ret != 0:
        raise OSError(errno, os.strerror(errno), path)


def getxattr(path, name, int size_guess=128):
    '''Get extended attribute
    
    If the caller knows the approximate size of the attribute value,
    it should be supplied in `size_guess`. If the guess turns out
    to be wrong, the system call has to be carried out three times
    (the first call will fail, the second determines the size and
    the third finally gets the value).
    '''

    cdef int ret
    cdef char* buf
    cdef int bufsize

    bufsize = size_guess
    buf = <char*> malloc(bufsize)

    if buf is NULL:
        # TODO: How to raise this exception?
        python_exc.PyErr_NoMemory()

    try:
        with nogil:
            ret = xattr.getxattr(path, name, &buf, bufsize)

        if ret < 0 and errno == ERANGE:
            with nogil:
                ret = xattr.getxattr(path, name, NULL, 0)
            if ret < 0:
                raise OSError(errno, os.strerror(errno), path)
            bufsize = ret
            free(buf)
            buf = <char*> malloc(bufsize)
            if buf is NULL:
                python_exc.PyErr_NoMemory()
                # TODO: What do we return now?
                return NULL

            with nogil:
                ret = xattr.getxattr(path, name, &buf, bufsize)

        if ret < 0:
            raise OSError(errno, os.strerror(errno), path)

        return PyString_FromStringAndSize(buf, ret)
    
    finally:
        free(buf)
        
