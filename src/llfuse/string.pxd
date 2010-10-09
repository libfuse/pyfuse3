'''
string.pxd

This file contains Cython definitions for string.h

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

cdef extern from "string.h":
    int strcmp(char *s1, char *s2)
