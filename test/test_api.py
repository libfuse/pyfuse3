#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
test_api.py - Unit tests for Python-LLFUSE.

Copyright © 2015 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
'''

from __future__ import division, print_function, absolute_import

if __name__ == '__main__':
    import pytest
    import sys
    sys.exit(pytest.main([__file__] + sys.argv[1:]))

import llfuse
import tempfile
import os
import errno
import pytest

def test_inquire_bits():
    assert 0 < llfuse.get_ino_t_bits() < 256
    assert 0 < llfuse.get_off_t_bits() < 256

def test_listdir():
    # There is a race-condition here if /usr/bin is modified while the test
    # runs - but hopefully this is sufficiently rare.
    list1 = set(os.listdir('/usr/bin'))
    list2 = set(llfuse.listdir('/usr/bin'))
    assert list1 == list2

def test_sup_groups():
    gids = llfuse.get_sup_groups(os.getpid())
    gids2 = set(os.getgroups())
    assert gids == gids2

def _getxattr_helper(path, name):
    try:
        value = llfuse.getxattr(path, name)
    except OSError as exc:
        errno = exc.errno
        value = None

    if not hasattr(os, 'getxattr'):
        return value

    try:
        value2 = os.getxattr(path, name)
    except OSError as exc:
        assert exc.errno == errno
    else:
        assert value2 is not None
        assert value2 == value

    return value

def test_entry_res():
    a = llfuse.EntryAttributes()
    val = 1000.2735
    a.st_atime_ns = val*1e9
    assert a.st_atime_ns / 1e9 == val

def test_xattr():
    with tempfile.NamedTemporaryFile() as fh:
        key = 'user.new_attribute'
        assert _getxattr_helper(fh.name, key) is None
        value = b'a nice little bytestring'

        try:
            llfuse.setxattr(fh.name, key, value)
        except OSError as exc:
            if exc.errno == errno.ENOTSUP:
                pytest.skip('ACLs not supported for %s' % fh.name)
            raise
        assert _getxattr_helper(fh.name, key) == value

        if not hasattr(os, 'setxattr'):
            return

        key = 'user.another_new_attribute'
        assert _getxattr_helper(fh.name, key) is None
        value = b'a nice little bytestring, but slightly modified'
        os.setxattr(fh.name, key, value)
        assert _getxattr_helper(fh.name, key) == value
