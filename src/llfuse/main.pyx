'''
main.pyx

This Cython source file is compiled into the llfuse.main module. It
provides the Python bindings to the low-level FUSE API.

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

from fuse_lowlevel cimport (fuse_args as fuse_args_t, fuse_lowlevel_new,
                            fuse_session, fuse_chan, fuse_session_add_chan,
                            fuse_mount, fuse_unmount, fuse_lowlevel_ops,
                            fuse_remove_signal_handlers,
                            fuse_set_signal_handlers,
                            fuse_session_destroy)
from libc cimport stdlib
from cpython.string cimport PyString_AsString
cimport cpython.exc

import logging
from llfuse.operations import Operations

log = logging.getLogger("fuse")

cdef object operations
cdef char* mountpoint
cdef fuse_session* session
cdef fuse_chan* channel
cdef fuse_lowlevel_ops fuse_ops

def init(operations_, char* mountpoint_, list args):
    '''Initialize and mount FUSE file system
            
    `operations_` has to be an instance of the `Operations` class (or another
    class defining the same methods).
    
    `args` has to be a list of strings. Valid options are listed in struct
    fuse_opt fuse_mount_opts[] (mount.c:68) and struct fuse_opt fuse_ll_opts[]
    (fuse_lowlevel_c:1526).
    '''

    log.debug('Initializing llfuse')

    if not isinstance(operations_, Operations):
        raise TypeError("first parameter must be Operations instance!")

    global operations
    global fuse_ops
    global mountpoint
    global session
    global channel

    # Give operations instance a chance to check and change the FUSE options
    operations_.check_args(args)

    mountpoint = mountpoint_
    operations = operations_
    fuse_args = make_fuse_args(args)
    
    log.debug('Calling fuse_mount')
    channel = fuse_mount(mountpoint, fuse_args)
    if not channel:
        raise RuntimeError('fuse_mount failed')

    log.debug('Calling fuse_lowlevel_new')
    session = fuse_lowlevel_new(fuse_args, &fuse_ops, sizeof(fuse_ops), NULL)
    if not session:
        fuse_unmount(mountpoint, channel)
        raise RuntimeError("fuse_lowlevel_new() failed")

    log.debug('Calling fuse_set_signal_handlers')
    if fuse_set_signal_handlers(session) == -1:
        fuse_session_destroy(session)
        fuse_unmount(mountpoint, channel)
        raise RuntimeError("fuse_set_signal_handlers() failed")

    log.debug('Calling fuse_session_add_chan')
    fuse_session_add_chan(session, channel)
    

cdef fuse_args_t* make_fuse_args(list args):
    cdef fuse_args_t* fuse_args
    fuse_args = <fuse_args_t*> stdlib.malloc(sizeof(fuse_args_t))

    if fuse_args is NULL:
        cpython.exc.PyErr_NoMemory()
        
    try:
        fuse_args.allocated = 1
        fuse_args.argc = len(args)
        fuse_args.argv = <char**> stdlib.malloc(fuse_args.argc * sizeof(char*))

        if fuse_args.argv is NULL:
            cpython.exc.PyErr_NoMemory()

        try:
            for (i, arg) in enumerate(args):
                fuse_args.argv[i] = PyString_AsString(arg)

            return fuse_args
        except:
            stdlib.free(fuse_args.argv)
            raise
    except:
        stdlib.free(fuse_args)
        raise

    
