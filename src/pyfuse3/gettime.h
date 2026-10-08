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
 * clock_gettime() is available on all supported platforms (Linux, FreeBSD,
 * NetBSD and macOS 10.12 or newer).
 */
#include <time.h>

static int gettime_realtime(struct timespec *tp) {
    return clock_gettime(CLOCK_REALTIME, tp);
}
