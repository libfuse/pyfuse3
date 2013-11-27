/*
capi.c

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of LLFUSE (http://python-llfuse.googlecode.com).
LLFUSE can be distributed under the terms of the GNU LGPL.
*/

#ifdef __gnu_linux__
#include "capi_linux.c"
#elif __FreeBSD__
#include "capi_freebsd.c"
#elif __APPLE__ && __MACH__
#include "capi_darwin.c"
#else
#error "Unable to determine system (Linux/FreeBSD/Darwin)"
#endif


