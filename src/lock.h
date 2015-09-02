/*
lock.h - Header file for lock.c

Copyright © 2015 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
*/


#ifndef _LLFUSE_LOCK_H_
#define _LLFUSE_LOCK_H_

#include <pthread.h>

int acquire(double timeout);
int release(void);
int c_yield(int count);
void init_lock(void);


#endif /* _LLFUSE_LOCK_H_ */
