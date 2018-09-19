/*
macros.c - Pre-processor macros

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
*/


/*
 * Macros to access the nanosecond attributes in struct stat in a
 * platform independent way. Stolen from fuse_misc.h.
 */

#if PLATFORM == PLATFORM_LINUX
#define GET_ATIME_NS(stbuf) ((stbuf)->st_atim.tv_nsec)
#define GET_CTIME_NS(stbuf) ((stbuf)->st_ctim.tv_nsec)
#define GET_MTIME_NS(stbuf) ((stbuf)->st_mtim.tv_nsec)
#define SET_ATIME_NS(stbuf, val) (stbuf)->st_atim.tv_nsec = (val)
#define SET_CTIME_NS(stbuf, val) (stbuf)->st_ctim.tv_nsec = (val)
#define SET_MTIME_NS(stbuf, val) (stbuf)->st_mtim.tv_nsec = (val)

#define GET_BIRTHTIME_NS(stbuf) (0)
#define GET_BIRTHTIME(stbuf) (0)
#define SET_BIRTHTIME_NS(stbuf, val) do {} while (0)
#define SET_BIRTHTIME(stbuf, val) do {} while (0)

/* BSD and OS-X */
#else
#define GET_BIRTHTIME(stbuf) ((stbuf)->st_birthtime)
#define SET_BIRTHTIME(stbuf, val) ((stbuf)->st_birthtime = (val))

#define GET_ATIME_NS(stbuf) ((stbuf)->st_atimespec.tv_nsec)
#define GET_CTIME_NS(stbuf) ((stbuf)->st_ctimespec.tv_nsec)
#define GET_MTIME_NS(stbuf) ((stbuf)->st_mtimespec.tv_nsec)
#define GET_BIRTHTIME_NS(stbuf) ((stbuf)->st_birthtimespec.tv_nsec)
#define SET_ATIME_NS(stbuf, val) ((stbuf)->st_atimespec.tv_nsec = (val))
#define SET_CTIME_NS(stbuf, val) ((stbuf)->st_ctimespec.tv_nsec = (val))
#define SET_MTIME_NS(stbuf, val) ((stbuf)->st_mtimespec.tv_nsec = (val))
#define SET_BIRTHTIME_NS(stbuf, val) ((stbuf)->st_birthtimespec.tv_nsec = (val))
#endif


#if PLATFORM == PLATFORM_LINUX || PLATFORM == PLATFORM_BSD
#define ASSIGN_DARWIN(x,y)
#define ASSIGN_NOT_DARWIN(x,y) ((x) = (y))
#elif PLATFORM == PLATFORM_DARWIN
#define ASSIGN_DARWIN(x,y) ((x) = (y))
#define ASSIGN_NOT_DARWIN(x,y)
#else
#error This should not happen
#endif
