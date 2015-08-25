/*
lock.c

This file provides the plain C components for the global lock.

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
*/

#include "lock.h"

#define TRUE  (1==1)
#define FALSE (0==1)

#include <pthread.h>
#include <time.h>
#include <errno.h>
#ifdef __MACH__
#include <sys/time.h>
#endif

#define GIGA ((long)1e9)

// Who was the last to acquire the lock
static pthread_t lock_owner;

// Is the lock currently taken
static int lock_taken = FALSE;

/* This variable indicates how many threads are currently waiting for
 * the lock. */
static int lock_wanted = 0;

/* Mutex for protecting access to lock_wanted, lock_owner and
 * lock_taken */
static pthread_mutex_t mutex;

/* Condition even to notify when the lock becomes available */
static pthread_cond_t cond;

void init_lock(void) {
    pthread_cond_init(&cond, NULL);
    pthread_mutex_init(&mutex, NULL);
}

int acquire(double timeout) {
    int ret;
    struct timespec abstime;
#ifdef __MACH__
    struct timeval tv;
#endif
    pthread_t me = pthread_self();

    if(timeout != 0) {
#ifdef __MACH__
        ret = gettimeofday(&tv, NULL);
        if(ret != 0) return ret;
        abstime.tv_sec = tv.tv_sec;
        abstime.tv_nsec = tv.tv_usec * 1000;
#else
        ret = clock_gettime(CLOCK_REALTIME, &abstime);
        if(ret != 0) return ret;
#endif
        abstime.tv_nsec += (long)(timeout - (int) timeout) * GIGA;
        if(abstime.tv_nsec >= GIGA) {
            abstime.tv_sec += abstime.tv_nsec / GIGA;
            abstime.tv_nsec = abstime.tv_nsec % GIGA;
        }
        abstime.tv_sec += (int) timeout;
    }

    ret = pthread_mutex_lock(&mutex);
    if(ret != 0) return ret;
    if(lock_taken) {
        if(pthread_equal(lock_owner, me)) {
            pthread_mutex_unlock(&mutex);
            return EDEADLK;
        }
        lock_wanted++;

        /* We need while here even though pthread_cond_signal wakes
         * only one thread:
         * http://stackoverflow.com/questions/8378789/forcing-a-thread-context-switch
         * http://en.wikipedia.org/wiki/Spurious_wakeup */
        if(timeout == 0)
            while(lock_taken) pthread_cond_wait(&cond, &mutex);
        else
            while(lock_taken) {
                ret = pthread_cond_timedwait(&cond, &mutex, &abstime);
                if(ret == ETIMEDOUT) {
                    lock_wanted--;
                    pthread_mutex_unlock(&mutex);
                    return ret;
                }

            }

        lock_wanted--;
    }
    lock_taken = TRUE;
    lock_owner = me;
    return pthread_mutex_unlock(&mutex);
}

int release(void) {
    int ret;
    if(!lock_taken)
        return EPERM;
    if(!pthread_equal(lock_owner, pthread_self()))
        return EPERM;
    ret = pthread_mutex_lock(&mutex);
    if(ret != 0) return ret;
    lock_taken = FALSE;
    if(lock_wanted > 0) {
        pthread_cond_signal(&cond);
    }
    return pthread_mutex_unlock(&mutex);
}

int c_yield(int count) {
    int ret;
    int i;
    pthread_t me = pthread_self();

    if(!lock_taken || !pthread_equal(lock_owner, me))
        return EPERM;
    ret = pthread_mutex_lock(&mutex);
    if(ret != 0) return ret;

    for(i=0; i < count; i++) {
        if(lock_wanted == 0)
            break;

        lock_taken = FALSE;
        lock_wanted++;
        pthread_cond_signal(&cond);
        // See acquire() for why 'while' is required
        do { pthread_cond_wait(&cond, &mutex); } while(lock_taken);
        lock_wanted--;
        if(lock_taken) {
            pthread_mutex_unlock(&mutex);
            return EPROTO;
        }
        if(pthread_equal(lock_owner, me)) {
            pthread_mutex_unlock(&mutex);
            return ENOMSG;
        }
        lock_taken = TRUE;
        lock_owner = me;
    }
    return pthread_mutex_unlock(&mutex);
}
