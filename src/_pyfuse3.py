'''
_pyfuse3.py

Compatibility redirect: Pure-Python components of pyfuse3.

Copyright © 2018 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

from pyfuse3 import _pyfuse3
import sys

sys.modules['_pyfuse3'] = _pyfuse3
