/*
 * syncfs.h
 *
 * Platform-independent interface to syncfs(2)
 *
 * This file is part of pyfuse3. This work may be distributed under the
 * terms of the GNU LGPL.
*/

#include <unistd.h>

/*
 * Linux
 */
#if PLATFORM == PLATFORM_LINUX

static int syncfs_p(int fd) {
    return syncfs(fd);
}

/*
 * FreeBSD, NetBSD & Darwin
 *
 * There is no syncfs(2) on these platforms, sync(2) flushes the buffers of
 * all mounted file systems instead. Note that sync(2) may return before the
 * data has actually been written to disk.
 */
#else

static int syncfs_p(int fd) {
    (void) fd;
    sync();
    return 0;
}

#endif
