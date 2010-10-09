/*
lock_c.c

This file provides the plain C components of lock.pyx. It is
included by the lock.c generated from lock.pyx by Cython.

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
*/


#include <pthread.h>

int acquire();
int release();
void init();

static pthread_mutex_t mutex;

inline void init()
{
    mutex = PTHREAD_ERRORCHECK_MUTEX_INITIALIZER_NP;
}

inline int acquire()
{
    return pthread_mutex_lock(&mutex);
}

inline int release()
{
    return pthread_mutex_unlock(&mutex);
}


