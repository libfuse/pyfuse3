'''
lock.pyx

This Cython source file is compiled into the llfuse.lock module. It
provides a global lock that can be used to explicitly control which
Python thread is running at a given time. (The GIL already enforces
that at most one Python thread is running, but it does not provide
means to control which thread that is).

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

# Include components written in plain C
cdef extern from "lock_c.c":
    int acquire() nogil
    int release() nogil
    void init() nogil
    int EINVAL
    int EDEADLK
    int EPERM

cdef extern from "sched.h":
    int sched_yield() nogil

cimport python_exc

cdef class Lock:
    '''
    This is the class of lock itself as well as a context manager to
    execute code while the global lock is being held.
    '''

    def acquire(self):
        '''Acquire global lock'''
        
        cdef int ret
        with nogil:
            ret = acquire()

        if ret == 0:
            return
        elif ret == EDEADLK:
            raise RuntimeError("Global lock cannot be acquired more than once")
        else:
            raise RuntimeError("pthread_lock_mutex returned errorcode %d" % ret)

    def release(self):
        '''Release global lock'''
        
        cdef int ret
        with nogil:
            ret = release()
            
        if ret == 0:
            return
        elif ret == EPERM:
            raise RuntimeError("Global lock can only be released by the holding thread")
        else:
            raise RuntimeError("pthread_unlock_mutex returned errorcode %d" % ret)

    def yield_(self):
        '''Yield global lock to a different thread'''

        cdef int ret1, ret2

        with nogil:
            ret1 = release()
            if ret1 !=  0:
                sched_yield()
                ret2 = acquire()

        if ret1 != 0:
            if ret1 == EPERM:
                raise RuntimeError("Global lock can only be released by the holding thread")
            else:
                raise RuntimeError("pthread_unlock_mutex returned errorcode %d" % ret1)
        elif ret2 != 0:
            raise RuntimeError("pthread_lock_mutex returned errorcode %d" % ret2)


    def without(self):
        '''Return context manager that releases the global lock'''
        
        return nolock

    __enter__ = acquire
    __exit__ = release

cdef class NoLockManager:
    '''Context manager to execute code while the global lock is released'''

    __enter__ = Lock.release
    __exit__ = Lock.acquire
    

with nogil:
    init()
lock = Lock()
nolock = NoLockManager()


