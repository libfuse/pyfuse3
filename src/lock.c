/*
lock.c

This file provides the plain C components for the global lock.

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
*/


#include <pthread.h>

int acquire(void);
int release(void);

static pthread_mutex_t mutex = PTHREAD_ERRORCHECK_MUTEX_INITIALIZER_NP;

inline int acquire(void)
{
    return pthread_mutex_lock(&mutex);
}

inline int release(void)
{
    return pthread_mutex_unlock(&mutex);
}


