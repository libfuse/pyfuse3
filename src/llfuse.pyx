'''
llfuse.pxy

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
'''

cdef extern from "llfuse.h":
    int PLATFORM
    enum:
        PLATFORM_LINUX
        PLATFORM_BSD
        PLATFORM_DARWIN

###########
# C IMPORTS
###########

from fuse_lowlevel cimport *
from pthread cimport *
from posix.stat cimport struct_stat, S_IFMT, S_IFDIR, S_IFREG
from posix.types cimport mode_t, dev_t, off_t
from libc.stdint cimport uint32_t
from libc.stdlib cimport const_char
from libc cimport stdlib, string, errno, dirent
from libc.errno cimport ETIMEDOUT, EPROTO, EINVAL, EPERM, ENOMSG, ENOATTR
from posix.unistd cimport getpid
from posix.time cimport timespec
from posix.signal cimport (sigemptyset, sigaddset, SIG_BLOCK, SIG_SETMASK,
                           siginfo_t, sigaction_t, sigaction, SA_SIGINFO)
from cpython.bytes cimport (PyBytes_AsStringAndSize, PyBytes_FromStringAndSize,
                            PyBytes_AsString, PyBytes_FromString, PyBytes_AS_STRING)
from cpython.buffer cimport (PyObject_GetBuffer, PyBuffer_Release,
                             PyBUF_CONTIG_RO, PyBUF_CONTIG)
cimport cpython.exc
cimport cython
from cpython.version cimport PY_MAJOR_VERSION
from libc cimport signal


######################
# EXTERNAL DEFINITIONS
######################

cdef extern from "lock.h" nogil:
    int acquire(double timeout) nogil
    int release() nogil
    int c_yield(int count) nogil
    int init_lock() nogil

cdef extern from "macros.c" nogil:
    long GET_BIRTHTIME(struct_stat* buf)
    long GET_ATIME_NS(struct_stat* buf)
    long GET_CTIME_NS(struct_stat* buf)
    long GET_MTIME_NS(struct_stat* buf)
    long GET_BIRTHTIME_NS(struct_stat* buf)

    void SET_BIRTHTIME(struct_stat* buf, long val)
    void SET_ATIME_NS(struct_stat* buf, long val)
    void SET_CTIME_NS(struct_stat* buf, long val)
    void SET_MTIME_NS(struct_stat* buf, long val)
    void SET_BIRTHTIME_NS(struct_stat* buf, long val)

    void ASSIGN_DARWIN(void*, void*)
    void ASSIGN_NOT_DARWIN(void*, void*)

    enum:
        NOTIFY_INVAL_INODE
        NOTIFY_INVAL_ENTRY

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

cdef extern from *:
    # Missing in the Cython provided libc/errno.pxd:
    enum:
        EDEADLK

cdef extern from "Python.h" nogil:
    void PyEval_InitThreads()
    int PY_SSIZE_T_MAX

# Actually passed as -D to cc (and defined in setup.py)
cdef extern from *:
    char* LLFUSE_VERSION

################
# PYTHON IMPORTS
################

import os
import logging
import sys
import os.path
import threading
from pickle import PicklingError

if PY_MAJOR_VERSION < 3:
    from Queue import Queue
    import contextlib2 as contextlib
    str_t = bytes
else:
    from queue import Queue
    str_t = str
    import contextlib

##################
# GLOBAL VARIABLES
##################

log = logging.getLogger("llfuse")
fse = sys.getfilesystemencoding()

cdef object operations
cdef object mountpoint_b
cdef fuse_session* session = NULL
cdef fuse_chan* channel = NULL
cdef fuse_lowlevel_ops fuse_ops
cdef object exc_info
cdef int exit_reason
cdef pthread_mutex_t exc_info_mutex

init_lock()
lock = Lock.__new__(Lock)
lock_released = NoLockManager.__new__(NoLockManager)

cdef object _notify_queue
_notify_queue = Queue(maxsize=1000)

# Exported for access from Python code
# (in the Cython source, we want ENOATTR to refer
#  to the C constant, not a Python object)
ROOT_INODE = FUSE_ROOT_ID
__version__ = LLFUSE_VERSION.decode('utf-8')
globals()['ENOATTR'] = ENOATTR

#######################
# FUSE REQUEST HANDLERS
#######################

include "operations.pxi"
include "handlers.pxi"

####################
# INTERNAL FUNCTIONS
####################

include "misc.pxi"

####################
# FUSE API FUNCTIONS
####################

include "fuse_api.pxi"
