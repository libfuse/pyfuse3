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

cimport cpython.exc
from libc cimport string, errno, stdlib, dirent, xattr
from cpython.bytes cimport PyBytes_AsStringAndSize, PyBytes_FromStringAndSize

def listdir(path):
    '''Like os.listdir(), but releases the GIL'''
    
    cdef dirent.DIR* dirp
    cdef dirent.dirent ent
    cdef dirent.dirent* res
    cdef int ret

    with nogil:
        dirp = dirent.opendir(path)
    names = list()

    while True:
        errno.errno = 0
        with nogil:
            ret = dirent.readdir_r(dirp, &ent, &res)
        if ret != 0:
            raise OSError(errno, os.strerror(errno), path)
        if res is NULL:
            break
        if string.strcmp(ent.d_name, b'.') == 0 or string.strcmp(ent.d_name, b'..') == 0:
            continue

        names.append(ent.d_name)
        
    with nogil:
        dirent.closedir(dirp)
    
    return names


def setxattr(path, name, value):
    '''Set extended attribute'''

    cdef int ret
    cdef Py_ssize_t n
    cdef char* s

    ret = PyBytes_AsStringAndSize(value, &s, &n)

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
    buf = <char*> stdlib.malloc(bufsize)

    if buf is NULL:
        cpython.exc.PyErr_NoMemory()

    try:
        with nogil:
            ret = xattr.getxattr(path, name, &buf, bufsize)

        if ret < 0 and errno.errno == errno.ERANGE:
            with nogil:
                ret = xattr.getxattr(path, name, NULL, 0)
            if ret < 0:
                raise OSError(errno, os.strerror(errno), path)
            bufsize = ret
            stdlib.free(buf)
            buf = <char*> stdlib.malloc(bufsize)
            if buf is NULL:
                cpython.exc.PyErr_NoMemory()

            with nogil:
                ret = xattr.getxattr(path, name, &buf, bufsize)

        if ret < 0:
            raise OSError(errno, os.strerror(errno), path)

        return PyBytes_FromStringAndSize(buf, ret)
    
    finally:
        stdlib.free(buf)
        
