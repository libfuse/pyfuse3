#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
test_api.py - Unit tests for pyfuse3.

Copyright © 2015 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

if __name__ == '__main__':
    import pytest
    import sys
    sys.exit(pytest.main([__file__] + sys.argv[1:]))

import pyfuse3
import tempfile
import os
import errno
import pytest
from copy import copy
from pickle import PicklingError

def test_listdir():
    # There is a race-condition here if /usr/bin is modified while the test
    # runs - but hopefully this is sufficiently rare.
    list1 = set(os.listdir('/usr/bin'))
    list2 = set(pyfuse3.listdir('/usr/bin'))
    assert list1 == list2

def test_sup_groups():
    gids = pyfuse3.get_sup_groups(os.getpid())
    gids2 = set(os.getgroups())
    assert gids == gids2

def test_syncfs():
    pyfuse3.syncfs('.')

def _getxattr_helper(path, name):
    try:
        value = pyfuse3.getxattr(path, name)
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
    a = pyfuse3.EntryAttributes()
    val = 1000.2735
    a.st_atime_ns = val*1e9
    assert a.st_atime_ns / 1e9 == val

def test_xattr():
    with tempfile.NamedTemporaryFile() as fh:
        key = 'user.new_attribute'
        assert _getxattr_helper(fh.name, key) is None
        value = b'a nice little bytestring'

        try:
            pyfuse3.setxattr(fh.name, key, value)
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

def test_copy():

    for obj in (pyfuse3.SetattrFields(),
                pyfuse3.RequestContext()):
        pytest.raises(PicklingError, copy, obj)

    for (inst, attr) in ((pyfuse3.EntryAttributes(), 'st_mode'),
                         (pyfuse3.StatvfsData(), 'f_files')):
        setattr(inst, attr, 42)
        inst_copy = copy(inst)
        assert getattr(inst, attr) == getattr(inst_copy, attr)

    inst = pyfuse3.FUSEError(10)
    assert inst.errno == copy(inst).errno
