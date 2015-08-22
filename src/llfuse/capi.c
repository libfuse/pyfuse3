/*
capi.c

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
*/

#ifdef __gnu_linux__
#include "capi_linux.c"
#elif __FreeBSD__
#include "capi_freebsd.c"
#elif __NetBSD__
#include "capi_freebsd.c"
#elif __APPLE__ && __MACH__
#include "capi_darwin.c"
#else
#error "Unable to determine system (Linux/FreeBSD/Darwin)"
#endif
