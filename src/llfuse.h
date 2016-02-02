/*
llfuse.h

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
*/


#define PLATFORM_LINUX 1
#define PLATFORM_BSD 2
#define PLATFORM_DARWIN 3

#ifdef __linux__
#define PLATFORM PLATFORM_LINUX
#elif __FreeBSD_kernel__&&__GLIBC__
#define PLATFORM PLATFORM_LINUX
#elif __FreeBSD__
#define PLATFORM PLATFORM_BSD
#elif __NetBSD__
#define PLATFORM PLATFORM_BSD
#elif __APPLE__ && __MACH__
#define PLATFORM PLATFORM_DARWIN
#else
#error "Unable to determine system (Linux/FreeBSD/NetBSD/Darwin)"
#endif

#if PLATFORM == PLATFORM_DARWIN
#include "darwin_compat.h"
#else
/* See also: Include/pthreads.pxd */
#include <semaphore.h>
#endif

#include <fuse.h>

#if FUSE_VERSION < 29
#error FUSE version too old, 2.9.0 or newer required
#endif

#if FUSE_MAJOR_VERSION != 2
#error This version of the FUSE library is not yet supported.
#endif
