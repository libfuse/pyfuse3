#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
test_rounding.py - Unit tests for pyfuse3.

Copyright © 2020 Philip Warner <philipwarner.info>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

if __name__ == '__main__':
    import pytest
    import sys
    sys.exit(pytest.main([__file__] + sys.argv[1:]))

import pyfuse3
from pyfuse3 import _NANOS_PER_SEC

def test_rounding():
    # Incorrect division previously resulted in rounding errors for
    # all dates.
    entry = pyfuse3.EntryAttributes()

    # Approximately 100 years, ending in 999
    secs = 100 * 365 * 24 * 3600 + 999
    nanos = _NANOS_PER_SEC - 1

    total = secs * _NANOS_PER_SEC + nanos
    
    entry.st_atime_ns = total
    entry.st_ctime_ns = total
    entry.st_mtime_ns = total
    # Birthtime skipped -- only valid under BSD and OSX
    #entry.st_birthtime_ns = total

    assert entry.st_atime_ns == total
    assert entry.st_ctime_ns == total
    assert entry.st_mtime_ns == total
    # Birthtime skipped -- only valid under BSD and OSX
    #assert entry.st_birthtime_ns == total
