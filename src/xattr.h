/*
 * xattr.h
 *
 * Platform-independent interface to extended attributes
 *
 * Copyright © 2015 Nikolaus Rath <Nikolaus.org>
 *
 * This file is part of Python-LLFUSE. This work may be distributed under the
 * terms of the GNU LGPL.
*/

#ifndef UNUSED
# if defined(__GNUC__)
#   if !(defined(__cplusplus)) || (__GNUC__ > 3 || (__GNUC__ == 3 && __GNUC_MINOR__ >= 4))
#     define UNUSED __attribute__ ((__unused__))
#   else
#     define UNUSED
#   endif
# else
#   define UNUSED
# endif
#endif

/*
 * Linux
 */
#if PLATFORM == PLATFORM_LINUX
#include <attr/xattr.h>

#define EXTATTR_NAMESPACE_USER 0
#define EXTATTR_NAMESPACE_SYSTEM 0
#define XATTR_NOFOLLOW 0
#define XATTR_NODEFAULT 0
#define XATTR_NOSECURITY 0

static ssize_t getxattr_p (char *path, char *name, void *value, size_t size,
                           UNUSED int namespace) {
    return getxattr(path, name, value, size);
}
static int setxattr_p (char *path, char *name, void *value, size_t size,
                       UNUSED int namespace) {
    return setxattr(path, name, value, size, 0);
}


/*
 * FreeBSD & NetBSD
 */
#elif PLATFORM == PLATFORM_BSD
#include <sys/types.h>
#include <sys/extattr.h>
#include <limits.h>

#define XATTR_NOFOLLOW 0
#define XATTR_NODEFAULT 0
#define XATTR_NOSECURITY 0

static ssize_t getxattr_p (char *path, char *name, void *value, size_t size,
                           int namespace) {
    /* If size > SSIZE_MAX, we cannot determine if we got all the data
       (because the return value doesn't fit into ssize_t) */
    if (size >= SSIZE_MAX) {
        errno = EINVAL;
        return -1;
    }

    ssize_t ret;
    ret = extattr_get_file(path, namespace, name, value, size);
    if (ret > 0 && <size_t> ret == size) {
        errno = ERANGE;
        return -1;
    }
    return ret;
}

static int setxattr_p (char *path, char *name, void *value, size_t size,
                       int namespace) {
    return extattr_set_file(path, namespace, name, value, size);
}


/*
 * Darwin
 */
#elif PLATFORM == PLATFORM_DARWIN
#include <sys/xattr.h>

#define EXTATTR_NAMESPACE_USER 0
#define EXTATTR_NAMESPACE_SYSTEM 0

static ssize_t getxattr_p (char *path, char *name, void *value, size_t size,
                           UNUSED int namespace) {
    return getxattr(path, name, value, size, 0, 0);
}
static int setxattr_p (char *path, char *name, void *value, size_t size,
                       UNUSED int namespace) {
    return setxattr(path, name, value, size, 0, 0);
}


/*
 * Unknown system
 */
#else
#error This should not happen
#endif
