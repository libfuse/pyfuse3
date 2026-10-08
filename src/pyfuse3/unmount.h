/*
 * unmount.h
 *
 * Platform-independent interface to unmount(2)
 *
 * This file is part of pyfuse3. This work may be distributed under the
 * terms of the GNU LGPL.
*/

#include <errno.h>

/*
 * Darwin
 */
#if PLATFORM == PLATFORM_DARWIN
#include <sys/param.h>
#include <sys/mount.h>

/* Forcibly unmount the file system mounted at *path*. */
static int force_unmount_p(const char *path) {
    return unmount(path, MNT_FORCE);
}

/*
 * Linux, FreeBSD & NetBSD
 *
 * Not needed, libfuse unmounts synchronously on these platforms.
 */
#else

static int force_unmount_p(const char *path) {
    (void) path;
    errno = ENOSYS;
    return -1;
}

#endif
