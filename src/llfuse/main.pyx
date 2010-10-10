'''
main.pyx

This Cython source file is compiled into the llfuse.main module. It
provides the Python bindings to the low-level FUSE API.

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

cimport fuse_lowlevel as fuse

import logging

log = logging.getLogger("fuse")

