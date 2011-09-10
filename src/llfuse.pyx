'''
llfuse.pyx

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of LLFUSE (http://python-llfuse.googlecode.com).
LLFUSE can be distributed under the terms of the GNU LGPL.
'''


# Version is defined in setup.py
cdef extern from *:
    char* LLFUSE_VERSION
__version__ = LLFUSE_VERSION


###########
# C IMPORTS
###########

from fuse_lowlevel cimport *
from libc.sys.stat cimport stat as c_stat, S_IFMT, S_IFDIR
from libc.sys.types cimport mode_t, dev_t, off_t
from libc.stdlib cimport const_char
from libc cimport stdlib, string, errno, dirent, xattr
from posix.unistd cimport getpid
from cpython.bytes cimport (PyBytes_AsStringAndSize, PyBytes_FromStringAndSize,
                            PyBytes_AsString, PyBytes_FromString)
cimport cpython.exc


######################
# EXTERNAL DEFINITIONS
######################

cdef extern from "sched.h":
    int sched_yield() nogil

cdef extern from "signal.h" nogil:
    int kill(pid_t pid, int sig)
    enum: SIGTERM

# Include components written in plain C
cdef extern from "lock.c" nogil:
    int acquire() nogil
    int release() nogil
    int EINVAL
    int EDEADLK
    int EPERM

cdef extern from "time.c" nogil:
    long GET_ATIME_NS(c_stat* buf)
    long GET_CTIME_NS(c_stat* buf)
    long GET_MTIME_NS(c_stat* buf)
    
    void SET_ATIME_NS(c_stat* buf, long val)
    void SET_CTIME_NS(c_stat* buf, long val)
    void SET_MTIME_NS(c_stat* buf, long val)

cdef extern from "Python.h" nogil:
    void PyEval_InitThreads()

cdef extern from "version.c":
    pass

################
# PYTHON IMPORTS
################

import os
import logging
import sys

##################
# GLOBAL VARIABLES
##################

log = logging.getLogger("fuse")

cdef object operations
cdef char* mountpoint = NULL
cdef fuse_session* session = NULL
cdef fuse_chan* channel = NULL
cdef fuse_lowlevel_ops fuse_ops
cdef object exc_info

lock = Lock.__new__(Lock)
lock_released = NoLockManager.__new__(NoLockManager)

# Exported for access from Python code
ROOT_INODE = FUSE_ROOT_ID
ENOATTR = errno.ENOATTR

#######################
# FUSE REQUEST HANDLERS
#######################
    
include "handlers.pxi"

####################
# INTERNAL FUNCTIONS
####################

include "misc.pxi"

####################
# FUSE API FUNCTIONS
####################

include "fuse_api.pxi"

##################
# Operations class
##################
        
include "operations.pxi"

