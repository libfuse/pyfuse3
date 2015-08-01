/*
version.c

This file provides the plain C components for checking the FUSE
version. Since we duplicate the information in the FUSE headers in our
*.pxd files, we have to make sure that this information does not get
out of sync (which may happen with a new major FUSE version).

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
*/


#include <fuse.h>

#if FUSE_MAJOR_VERSION != 2
#error This version of the FUSE library is not yet supported.
#endif
