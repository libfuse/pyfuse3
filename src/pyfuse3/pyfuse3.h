/*
pyfuse3.h

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
*/

#define PLATFORM_LINUX 1
#define PLATFORM_BSD 2
#define PLATFORM_DARWIN 3

#ifdef __linux__
#define PLATFORM PLATFORM_LINUX
#elif __FreeBSD_kernel__ && __GLIBC__
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

#include <fuse.h>

#if FUSE_VERSION < 32
#error FUSE version too old, 3.2.0 or newer required
#endif

/*
 * On macOS, libfuse is provided by macFUSE. Its headers offer two variants of
 * the low-level API, selected by FUSE_DARWIN_ENABLE_EXTENSIONS: the vanilla
 * libfuse API (using struct stat, struct fuse_entry_param and struct statvfs)
 * and an extended API using Darwin specific structures. pyfuse3 uses the
 * vanilla API, so that the same Cython code works on all platforms. The build
 * backend passes -DFUSE_DARWIN_ENABLE_EXTENSIONS=0 to the compiler.
 */
#if PLATFORM == PLATFORM_DARWIN && FUSE_DARWIN_ENABLE_EXTENSIONS
#error pyfuse3 must be compiled with -DFUSE_DARWIN_ENABLE_EXTENSIONS=0
#endif

/*
 * Flags for the rename() request. On Linux, these are provided by the kernel
 * headers. macFUSE defines them in terms of the RENAME_SWAP/RENAME_EXCL flags
 * of renameatx_np(2). Other platforms do not have them, define them as unique
 * values so that the flag checks in the rename handler still work.
 */
#if PLATFORM == PLATFORM_LINUX
#include <linux/fs.h>
#endif
#ifndef RENAME_NOREPLACE
#define RENAME_NOREPLACE (1 << 0)
#endif
#ifndef RENAME_EXCHANGE
#define RENAME_EXCHANGE (1 << 1)
#endif
