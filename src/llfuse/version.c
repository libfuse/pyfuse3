/*
version.c

This file provides the plain C components for checking the FUSE
version. Since we duplicate the information in the FUSE headers in our
*.pxd files, we have to make sure that this information does not get
out of sync (which may happen with a new major FUSE version).

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
*/


#include <fuse.h>

#if FUSE_MAJOR_VERSION != 2
#error This version of the FUSE library is not yet supported.
#endif

