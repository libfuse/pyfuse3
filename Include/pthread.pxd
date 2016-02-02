'''
pthreads.pxd

This file contains Cython definitions for pthread.h

Copyright © 2015 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
'''

from posix.signal cimport sigset_t

cdef extern from "<pthread.h>" nogil:
    # POSIX says this might be a struct, but CPython (and llfuse)
    # rely on it being an integer.
    ctypedef int pthread_t

    ctypedef struct pthread_attr_t:
        pass
    ctypedef struct pthread_mutexattr_t:
        pass
    ctypedef struct pthread_mutex_t:
       pass

    enum:
        PTHREAD_CANCEL_ENABLE
        PTHREAD_CANCEL_DISABLE

    int pthread_cancel(pthread_t thread)
    int pthread_setcancelstate(int state, int *oldstate)
    pthread_t pthread_self()
    int pthread_sigmask(int how, sigset_t *set, sigset_t *oldset)
    int pthread_equal(pthread_t t1, pthread_t t2)
    int pthread_create(pthread_t *thread, pthread_attr_t *attr,
                       void *(*start_routine) (void *), void *arg)
    int pthread_join(pthread_t thread, void **retval)

    int pthread_mutex_init(pthread_mutex_t *mutex, pthread_mutexattr_t *mutexattr)
    int pthread_mutex_lock(pthread_mutex_t *mutex)
    int pthread_mutex_unlock(pthread_mutex_t *mutex)

# The sem_* functions actually need the semaphone.h header file.  However, under
# OS-X we use a compatibility layer that breaks if we include the native
# semaphore.h file. Therefore, we pretend that no header file is required and
# conditionally include semaphore.h in llfuse.h.
cdef extern from * nogil:
    ctypedef struct sem_t:
        pass

    int sem_init(sem_t *sem, int pshared, unsigned int value)
    int sem_post(sem_t *sem)
    int sem_wait(sem_t *sem)
