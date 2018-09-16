/*
 * gettime.h
 *
 * Platform-independent interface to system clock
 *
 * Copyright © 2015 Nikolaus Rath <Nikolaus.org>
 *
 * This file is part of pyfuse3. This work may be distributed under the
 * terms of the GNU LGPL.
*/

/*
 * Linux
 */
#if PLATFORM == PLATFORM_LINUX
#include <time.h>

static int gettime_realtime(struct timespec *tp) {
    return clock_gettime(CLOCK_REALTIME, tp);
}


/*
 * FreeBSD & NetBSD
 */
#elif PLATFORM == PLATFORM_BSD
#include <time.h>

static int gettime_realtime(struct timespec *tp) {
    return clock_gettime(CLOCK_REALTIME, tp);
}

/*
 * Darwin
 */
#elif PLATFORM == PLATFORM_DARWIN
#include <sys/time.h>

static int gettime_realtime(struct timespec *tp) {
    struct timeval tv;
    int res;

    res = gettimeofday(&tv, NULL);
    if(res != 0)
        return -1;

    tp->tv_sec = tv.tv_sec;
    tp->tv_nsec = tv.tv_usec * 1000;

    return 0;
}


/*
 * Unknown system
 */
#else
#error This should not happen
#endif
