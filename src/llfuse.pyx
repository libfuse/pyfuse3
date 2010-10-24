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

from fuse_lowlevel cimport (fuse_args as fuse_args_t, fuse_lowlevel_new,
                            fuse_session, fuse_chan, fuse_session_add_chan,
                            fuse_mount, fuse_unmount, fuse_lowlevel_ops,
                            fuse_remove_signal_handlers, fuse_conn_info,
                            fuse_set_signal_handlers, fuse_req_t, ulong_t,
                            fuse_session_destroy, fuse_ino_t, fuse_file_info,
                            fuse_session_loop, fuse_session_loop_mt,
                            fuse_session_remove_chan, fuse_reply_err,
                            fuse_reply_entry, fuse_entry_param)
from libc.sys.stat cimport stat as c_stat, S_IFMT, S_IFDIR
from libc.sys.types cimport mode_t, dev_t, off_t
from libc.stdlib cimport const_char
from libc cimport stdlib, string, errno, dirent, xattr
from cpython.bytes cimport (PyBytes_AsStringAndSize, PyBytes_FromStringAndSize,
                            PyBytes_AsString, PyBytes_FromString)
cimport cpython.exc

######################
# EXTERNAL DEFINITIONS
######################

cdef extern from "sched.h":
    int sched_yield() nogil

# Include components written in plain C
cdef extern from "lock.c" nogil:
    int acquire() nogil
    int release() nogil
    int EINVAL
    int EDEADLK
    int EPERM

cdef extern from "time.c" nogil:
    int GET_ATIME_NS(c_stat* buf)
    int GET_CTIME_NS(c_stat* buf)
    int GET_MTIME_NS(c_stat* buf)
    
    void SET_ATIME_NS(c_stat* buf, int val)
    void SET_CTIME_NS(c_stat* buf, int val)
    void SET_MTIME_NS(c_stat* buf, int val)


################
# PYTHON IMPORTS
################

import errno
import os
import logging

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

