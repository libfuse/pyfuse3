/*
time.c

Functions to access the nanosecond attributes in struct stat
in a platform independent way. Stolen from fuse_misc.h.

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of LLFUSE (http://python-llfuse.googlecode.com).
LLFUSE can be distributed under the terms of the GNU LGPL.
*/


/* Linux */
#ifdef HAVE_STRUCT_STAT_ST_ATIM
#define GET_ATIME_NS(stbuf) ((stbuf)->st_atim.tv_nsec)
#define GET_CTIME_NS(stbuf) ((stbuf)->st_ctim.tv_nsec)
#define GET_MTIME_NS(stbuf) ((stbuf)->st_mtim.tv_nsec)
#define SET_ATIME_NS(stbuf, val) (stbuf)->st_atim.tv_nsec = (val)
#define SET_CTIME_NS(stbuf, val) (stbuf)->st_ctim.tv_nsec = (val)
#define SET_MTIME_NS(stbuf, val) (stbuf)->st_mtim.tv_nsec = (val)

/* FreeBSD */
#elif defined(HAVE_STRUCT_STAT_ST_ATIMESPEC)
#define GET_ATIME_NS(stbuf) ((stbuf)->st_atimespec.tv_nsec)
#define GET_CTIME_NS(stbuf) ((stbuf)->st_ctimespec.tv_nsec)
#define GET_MTIME_NS(stbuf) ((stbuf)->st_mtimespec.tv_nsec)
#define SET_ATIME_NS(stbuf, val) (stbuf)->st_atimespec.tv_nsec = (val)
#define SET_CTIME_NS(stbuf, val) (stbuf)->st_ctimespec.tv_nsec = (val)
#define SET_MTIME_NS(stbuf, val) (stbuf)->st_mtimespec.tv_nsec = (val)

/* No nanosecond resolution */
#else
#define GET_ATIME_NS(stbuf) 0
#define GET_CTIME_NS(stbuf) 0
#define GET_MTIME_NS(stbuf) 0
#define SET_ATIME_NS(stbuf, val) do { } while (0)
#define SET_CTIME_NS(stbuf, val) do { } while (0)
#define SET_MTIME_NS(stbuf, val) do { } while (0)
#endif
