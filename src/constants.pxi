'''
constants.pxi

This file gives Python-level access to a number of constants defined
by libfuse. It is included by pyfuse3.pyx.

Copyright © 2018 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

cdef extern from "<linux/fs.h>" nogil:
  enum:
    RENAME_EXCHANGE
    RENAME_NOREPLACE

ROOT_INODE = FUSE_ROOT_ID
__version__ = PYFUSE3_VERSION.decode('utf-8')

# In the Cython source, we want the names to refer to the
# C constants. Therefore, we assign through globals().
g = globals()
g['ENOATTR'] = ENOATTR
g['RENAME_EXCHANGE'] = RENAME_EXCHANGE
g['RENAME_NOREPLACE'] = RENAME_NOREPLACE
