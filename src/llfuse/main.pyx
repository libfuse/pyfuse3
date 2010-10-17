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
                            fuse_remove_signal_handlers, fuse_conn_info,
                            fuse_set_signal_handlers, fuse_req_t, ulong_t,
                            fuse_session_destroy, fuse_ino_t, fuse_file_info,
                            fuse_session_loop, fuse_session_loop_mt,
                            fuse_session_remove_chan)
from libc.sys.stat cimport stat
from libc.sys.types cimport mode_t, dev_t, off_t
from libc.stdlib cimport const_char
from libc cimport stdlib, string
from cpython.bytes cimport PyBytes_AsString
cimport cpython.exc
from llfuse.lock import lock, lock_released

import logging
import errno

log = logging.getLogger("fuse")

cdef object operations
cdef char* mountpoint = NULL
cdef fuse_session* session = NULL
cdef fuse_chan* channel = NULL
cdef fuse_lowlevel_ops fuse_ops


class FUSEError(Exception):
    '''Wrapped errno value to be returned to the fuse kernel module

    This exception can store only an errno. Request handlers should raise
    it to return a specific errno to the fuse kernel module.
    '''

    __slots__ = [ 'errno' ]

    def __init__(self, errno_):
        super(FUSEError, self).__init__()
        self.errno = errno_

    def __str__(self):
        # errno may not have strings for all error codes
        return errno.errorcode.get(self.errno, str(self.errno))

    
cdef void fuse_init (void *userdata, fuse_conn_info *conn) with gil:
    with lock:
        operations.init()

cdef void fuse_destroy (void *userdata):
    pass

cdef void fuse_lookup (fuse_req_t req, fuse_ino_t parent, const_char *name):
    pass

cdef void fuse_forget (fuse_req_t req, fuse_ino_t ino, ulong_t nlookup):
    pass

cdef void fuse_getattr (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi):
    pass

cdef void fuse_setattr (fuse_req_t req, fuse_ino_t ino, stat *attr,
                        int to_set, fuse_file_info *fi):
    pass

cdef void fuse_readlink (fuse_req_t req, fuse_ino_t ino):
    pass

cdef void fuse_mknod (fuse_req_t req, fuse_ino_t parent, const_char *name,
                      mode_t mode, dev_t rdev):
    pass

cdef void fuse_mkdir (fuse_req_t req, fuse_ino_t parent, const_char *name,
                      mode_t mode):
    pass

cdef void fuse_unlink (fuse_req_t req, fuse_ino_t parent, const_char *name):
    pass

cdef void fuse_rmdir (fuse_req_t req, fuse_ino_t parent, const_char *name):
    pass

cdef void fuse_symlink (fuse_req_t req, const_char *link, fuse_ino_t parent,
                        const_char *name):
    pass

cdef void fuse_rename (fuse_req_t req, fuse_ino_t parent, const_char *name,
                       fuse_ino_t newparent, const_char *newname):
    pass

cdef void fuse_link (fuse_req_t req, fuse_ino_t ino, fuse_ino_t newparent,
                     const_char *newname):
    pass

cdef void fuse_open (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi):
    pass

cdef void fuse_read (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                     fuse_file_info *fi):
    pass

cdef void fuse_write (fuse_req_t req, fuse_ino_t ino, const_char *buf,
                      size_t size, off_t off, fuse_file_info *fi):
    pass

cdef void fuse_flush (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi):
    pass

cdef void fuse_release (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi):
    pass

cdef void fuse_fsync (fuse_req_t req, fuse_ino_t ino, int datasync,
                      fuse_file_info *fi):
    pass

cdef void fuse_opendir (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi):
    pass

cdef void fuse_readdir (fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
                        fuse_file_info *fi):
    pass

cdef void fuse_releasedir (fuse_req_t req, fuse_ino_t ino, fuse_file_info *fi):
    pass

cdef void fuse_fsyncdir (fuse_req_t req, fuse_ino_t ino, int datasync,
                         fuse_file_info *fi):
    pass

cdef void fuse_statfs (fuse_req_t req, fuse_ino_t ino):
    pass

cdef void fuse_setxattr (fuse_req_t req, fuse_ino_t ino, const_char *name,
                         const_char *value, size_t size, int flags):
    pass

cdef void fuse_getxattr (fuse_req_t req, fuse_ino_t ino, const_char *name, size_t size):
    pass

cdef void fuse_listxattr (fuse_req_t req, fuse_ino_t ino, size_t size):
    pass

cdef void fuse_removexattr (fuse_req_t req, fuse_ino_t ino, const_char *name):
    pass

cdef void fuse_access (fuse_req_t req, fuse_ino_t ino, int mask):
    pass

cdef void fuse_create (fuse_req_t req, fuse_ino_t parent, const_char *name,
                       mode_t mode, fuse_file_info *fi):
    pass


cdef void init_fuse_ops():
    '''Initialize fuse_lowlevel_ops structure'''

    string.memset(&fuse_ops, 0, sizeof(fuse_lowlevel_ops))

    fuse_ops.init = fuse_init
    fuse_ops.destroy = fuse_destroy
    fuse_ops.lookup = fuse_lookup
    fuse_ops.forget = fuse_forget
    fuse_ops.getattr = fuse_getattr
    fuse_ops.setattr = fuse_setattr
    fuse_ops.readlink = fuse_readlink
    fuse_ops.mknod = fuse_mknod
    fuse_ops.mkdir = fuse_mkdir
    fuse_ops.unlink = fuse_unlink
    fuse_ops.rmdir = fuse_rmdir
    fuse_ops.symlink = fuse_symlink
    fuse_ops.rename = fuse_rename
    fuse_ops.link = fuse_link
    fuse_ops.open = fuse_open
    fuse_ops.read = fuse_read
    fuse_ops.write = fuse_write
    fuse_ops.flush = fuse_flush
    fuse_ops.release = fuse_release
    fuse_ops.fsync = fuse_fsync
    fuse_ops.opendir = fuse_opendir
    fuse_ops.readdir = fuse_readdir
    fuse_ops.releasedir = fuse_releasedir
    fuse_ops.fsyncdir = fuse_fsyncdir
    fuse_ops.statfs = fuse_statfs
    fuse_ops.setxattr = fuse_setxattr
    fuse_ops.getxattr = fuse_getxattr
    fuse_ops.listxattr = fuse_listxattr
    fuse_ops.removexattr = fuse_removexattr
    fuse_ops.access = fuse_access
    fuse_ops.create = fuse_create


def init(operations_, char* mountpoint_, list args):
    '''Initialize and mount FUSE file system
            
    `operations_` has to be an instance of the `Operations` class (or another
    class defining the same methods).
    
    `args` has to be a list of strings. Valid options are listed in struct
    fuse_opt fuse_mount_opts[] (mount.c:68) and struct fuse_opt fuse_ll_opts[]
    (fuse_lowlevel_c:1526).
    '''

    log.debug('Initializing llfuse')

    from llfuse.operations import Operations
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
    init_fuse_ops()
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
                fuse_args.argv[i] = PyBytes_AsString(arg)

            return fuse_args
        except:
            stdlib.free(fuse_args.argv)
            raise
    except:
        stdlib.free(fuse_args)
        raise

    
def main(single=False):
    '''Run FUSE main loop'''

    if session == NULL:
        raise RuntimeError('Need to call init() before main()')

    if single:
        log.debug('Calling fuse_session_loop')
        # We need to unlock even in single threaded mode, because the
        # Operations methods will always try to acquire the lock
        with lock_released:
            if fuse_session_loop(session) != 0:
                raise RuntimeError("fuse_session_loop() failed")
    else:
        log.debug('Calling fuse_session_loop_mt')
        with lock_released:
            if fuse_session_loop_mt(session) != 0:
                raise RuntimeError("fuse_session_loop_mt() failed")

def close():
    '''Unmount file system and clean up'''

    global mountpoint
    global session
    global channel

    log.debug('Calling fuse_session_remove_chan')
    fuse_session_remove_chan(channel)
    log.debug('Calling fuse_remove_signal_handlers')
    fuse_remove_signal_handlers(session)
    log.debug('Calling fuse_session_destroy')
    fuse_session_destroy(session)
    log.debug('Calling fuse_unmount')
    fuse_unmount(mountpoint, channel)

    mountpoint = NULL
    session = NULL
    channel = NULL
