# -*- coding: utf-8 -*-
'''
__init__.py

Copyright © 2010 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.

'''

from __future__ import division, print_function, absolute_import

from llfuse.operations import *
from llfuse.cext import *

# dunder needs explicit import
from .cext import __version__

# For easy access
ENOATTR = ENOATTR_obj
