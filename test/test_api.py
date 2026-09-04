#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
test_api.py - Unit tests for pyfuse3.

Copyright © 2015 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

if __name__ == '__main__':
    import sys

    import pytest

    sys.exit(pytest.main([__file__] + sys.argv[1:]))

import errno
import os
import platform
import tempfile
from copy import copy
from pickle import PicklingError

import pytest

import pyfuse3
from pyfuse3 import EntryAttributes, RequestContext, SetattrFields, StatvfsData


def test_listdir():
    # There is a race-condition here if /usr/bin is modified while the test
    # runs - but hopefully this is sufficiently rare.
    list1 = set(os.listdir('/usr/bin'))
    list2 = set(pyfuse3.listdir('/usr/bin'))
    assert list1 == list2


def test_sup_groups():
    gids = pyfuse3.get_sup_groups(os.getpid())
    gids2 = set(os.getgroups())
    if platform.system() == 'Darwin':
        # The kernel stores at most 16 group ids in the process credentials
        # (which is what get_sup_groups() returns), while os.getgroups() also
        # returns the groups that macOS resolves through Open Directory.
        assert gids
        assert gids <= gids2
    else:
        assert gids == gids2


def test_syncfs():
    pyfuse3.syncfs('.')


def _getxattr_helper(path, name):
    errno = None
    try:
        value = pyfuse3.getxattr(path, name)
    except OSError as exc:
        errno = exc.errno
        value = None

    # Only available on Linux
    os_getxattr = getattr(os, 'getxattr', None)
    if os_getxattr is None:
        return value

    try:
        value2 = os_getxattr(path, name)
    except OSError as exc:
        assert exc.errno == errno
    else:
        assert value2 is not None
        assert value2 == value

    return value


def test_entry_res():
    a = EntryAttributes()
    val = 1000.2735
    a.st_atime_ns = int(val * 1e9)
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
                pytest.skip('xattrs not supported for %s' % fh.name)
            raise
        assert _getxattr_helper(fh.name, key) == value

        # Only available on Linux
        os_setxattr = getattr(os, 'setxattr', None)
        if os_setxattr is None:
            return

        key = 'user.another_new_attribute'
        assert _getxattr_helper(fh.name, key) is None
        value = b'a nice little bytestring, but slightly modified'
        os_setxattr(fh.name, key, value)
        assert _getxattr_helper(fh.name, key) == value


def test_copy():
    for obj in (SetattrFields(), RequestContext()):
        pytest.raises(PicklingError, copy, obj)

    for inst, attr in ((EntryAttributes(), 'st_mode'), (StatvfsData(), 'f_files')):
        setattr(inst, attr, 42)
        inst_copy = copy(inst)
        assert getattr(inst, attr) == getattr(inst_copy, attr)

    exc = pyfuse3.FUSEError(10)
    assert exc.errno == copy(exc).errno
