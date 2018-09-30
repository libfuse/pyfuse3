'''
libc_extra.pxd

This file contains Cython definitions libc functions that are not included in
the pxd files shipped with Cython.

Copyright © 2010 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

from posix.time cimport timespec

cdef extern from "<dirent.h>" nogil:
    ctypedef struct DIR:
        pass
    cdef struct dirent:
        char* d_name

    dirent* readdir(DIR* dirp)
    int readdir_r(DIR *dirp, dirent *entry, dirent **result)

cdef extern from "<sys/types.h>" nogil:
    DIR *opendir(char *name)
    int closedir(DIR* dirp)

cdef extern from "<sys/statvfs.h>" nogil:
    ctypedef int fsblkcnt_t
    ctypedef int fsfilcnt_t

    struct statvfs:
        unsigned long f_bsize
        unsigned long f_frsize
        fsblkcnt_t     f_blocks
        fsblkcnt_t     f_bfree
        fsblkcnt_t     f_bavail
        fsfilcnt_t     f_files
        fsfilcnt_t     f_ffree
        fsfilcnt_t     f_favail
        unsigned long  f_namemax

cdef extern from "xattr.h" nogil:
    int setxattr_p (char *path, char *name,
                    void *value, int size, int namespace)

    ssize_t getxattr_p (char *path, char *name,
                        void *value, int size, int namespace)

    enum:
        EXTATTR_NAMESPACE_SYSTEM
        EXTATTR_NAMESPACE_USER
        XATTR_CREATE
        XATTR_REPLACE
        XATTR_NOFOLLOW
        XATTR_NODEFAULT
        XATTR_NOSECURITY


cdef extern from "gettime.h" nogil:
    int gettime_realtime(timespec *tp)

cdef extern from "<unistd.h>" nogil:
    int syncfs(int fd)
