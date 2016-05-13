#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
test_fs.py - Unit tests for Python-LLFUSE.

Copyright © 2015 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
'''

from __future__ import division, print_function, absolute_import
import pytest
import sys

if __name__ == '__main__':
    sys.exit(pytest.main([__file__] + sys.argv[1:]))

import llfuse
from llfuse import FUSEError
import multiprocessing
import os
import errno
import stat
import time
import logging
import threading
from util import skip_if_no_fuse, wait_for_mount, umount, cleanup, wait_for

skip_if_no_fuse()


@pytest.yield_fixture()
def testfs(tmpdir):

    # We can't use forkserver because we have to make sure
    # that the server inherits the per-test stdout/stderr file
    # descriptors.
    if hasattr(multiprocessing, 'get_context'):
        mp = multiprocessing.get_context('fork')
    else:
        # Older versions only support *fork* anyway
        mp = multiprocessing
    if threading.active_count() != 1:
        raise RuntimeError("Multi-threaded test running is not supported")

    mnt_dir = str(tmpdir)
    with mp.Manager() as mgr:
        cross_process = mgr.Namespace()
        mount_process = mp.Process(target=run_fs,
                                   args=(mnt_dir, cross_process))

        mount_process.start()
        try:
            wait_for_mount(mount_process, mnt_dir)
            yield (mnt_dir, cross_process)
        except:
            cleanup(mnt_dir)
            raise
        else:
            umount(mount_process, mnt_dir)

def test_invalidate_entry(testfs):
    (mnt_dir, fs_state) = testfs
    path = os.path.join(mnt_dir, 'message')
    os.stat(path)
    assert fs_state.lookup_called
    fs_state.lookup_called = False
    os.stat(path)
    assert not fs_state.lookup_called

    # Unfortunately there's no way to determine when the
    # kernel has processed the forget() request, so we
    # wait longer and longer until it works.
    def check(_wait_time=[0.01]):
        llfuse.setxattr(mnt_dir, 'command', b'forget_entry')
        time.sleep(_wait_time[0])
        fs_state.lookup_called = False
        os.stat(path)
        _wait_time[0] += max(1, _wait_time[0])
        return fs_state.lookup_called
    assert wait_for(check)

def test_invalidate_inode(testfs):
    (mnt_dir, fs_state) = testfs
    with open(os.path.join(mnt_dir, 'message'), 'r') as fh:
        assert fh.read() == 'hello world\n'
        assert fs_state.read_called
        fs_state.read_called = False
        fh.seek(0)
        assert fh.read() == 'hello world\n'
        assert not fs_state.read_called

        # Unfortunately there's no way to determine when the
        # kernel has processed the forget() request, so we
        # wait longer and longer until it works.
        def check(_wait_time=[0.01]):
            llfuse.setxattr(mnt_dir, 'command', b'forget_inode')
            time.sleep(_wait_time[0])
            fs_state.read_called = False
            fh.seek(0)
            assert fh.read() == 'hello world\n'
            _wait_time[0] += max(1, _wait_time[0])
            return fs_state.read_called
        assert wait_for(check)

def test_notify_store(testfs):
    (mnt_dir, fs_state) = testfs
    with open(os.path.join(mnt_dir, 'message'), 'r') as fh:
        llfuse.setxattr(mnt_dir, 'command', b'store')
        fs_state.read_called = False
        assert fh.read() == 'hello world\n'
        assert not fs_state.read_called

def test_entry_timeout(testfs):
    (mnt_dir, fs_state) = testfs
    fs_state.entry_timeout = 1
    path = os.path.join(mnt_dir, 'message')

    os.stat(path)
    assert fs_state.lookup_called
    fs_state.lookup_called = False
    os.stat(path)
    assert not fs_state.lookup_called

    time.sleep(fs_state.entry_timeout*1.1)
    fs_state.lookup_called = False
    os.stat(path)
    assert fs_state.lookup_called

def test_attr_timeout(testfs):
    (mnt_dir, fs_state) = testfs
    fs_state.attr_timeout = 1
    with open(os.path.join(mnt_dir, 'message'), 'r') as fh:
        os.fstat(fh.fileno())
        assert fs_state.getattr_called
        fs_state.getattr_called = False
        os.fstat(fh.fileno())
        assert not fs_state.getattr_called

        time.sleep(fs_state.attr_timeout*1.1)
        fs_state.getattr_called = False
        os.fstat(fh.fileno())
        assert fs_state.getattr_called

class Fs(llfuse.Operations):
    def __init__(self, cross_process):
        super(Fs, self).__init__()
        self.hello_name = b"message"
        self.hello_inode = llfuse.ROOT_INODE+1
        self.hello_data = b"hello world\n"
        self.status = cross_process
        self.lookup_cnt = 0
        self.status.getattr_called = False
        self.status.lookup_called = False
        self.status.read_called = False
        self.status.entry_timeout = 2
        self.status.attr_timeout = 2

    def getattr(self, inode, ctx=None):
        entry = llfuse.EntryAttributes()
        if inode == llfuse.ROOT_INODE:
            entry.st_mode = (stat.S_IFDIR | 0o755)
            entry.st_size = 0
        elif inode == self.hello_inode:
            entry.st_mode = (stat.S_IFREG | 0o644)
            entry.st_size = len(self.hello_data)
        else:
            raise llfuse.FUSEError(errno.ENOENT)

        stamp = int(1438467123.985654*1e9)
        entry.st_atime_ns = stamp
        entry.st_ctime_ns = stamp
        entry.st_mtime_ns = stamp
        entry.st_gid = os.getgid()
        entry.st_uid = os.getuid()
        entry.st_ino = inode
        entry.entry_timeout = self.status.entry_timeout
        entry.attr_timeout = self.status.attr_timeout

        self.status.getattr_called = True
        return entry

    def forget(self, inode_list):
        for (inode, cnt) in inode_list:
            if inode == self.hello_inode:
                self.lookup_cnt -= 1
                assert self.lookup_cnt >= 0
            else:
                assert inode == llfuse.ROOT_INODE

    def lookup(self, parent_inode, name, ctx=None):
        if parent_inode != llfuse.ROOT_INODE or name != self.hello_name:
            raise llfuse.FUSEError(errno.ENOENT)
        self.lookup_cnt += 1
        self.status.lookup_called = True
        return self.getattr(self.hello_inode)

    def opendir(self, inode, ctx):
        if inode != llfuse.ROOT_INODE:
            raise llfuse.FUSEError(errno.ENOENT)
        return inode

    def readdir(self, fh, off):
        assert fh == llfuse.ROOT_INODE
        if off == 0:
            yield (self.hello_name, self.getattr(self.hello_inode), 1)

    def open(self, inode, flags, ctx):
        if inode != self.hello_inode:
            raise llfuse.FUSEError(errno.ENOENT)
        if flags & os.O_RDWR or flags & os.O_WRONLY:
            raise llfuse.FUSEError(errno.EPERM)
        return inode

    def read(self, fh, off, size):
        assert fh == self.hello_inode
        self.status.read_called = True
        return self.hello_data[off:off+size]

    def setxattr(self, inode, name, value, ctx):
        if inode != llfuse.ROOT_INODE or name != b'command':
            raise FUSEError(errno.ENOTSUP)

        if value == b'forget_entry':
            llfuse.invalidate_entry(llfuse.ROOT_INODE, self.hello_name)
        elif value == b'forget_inode':
            llfuse.invalidate_inode(self.hello_inode)
        elif value == b'store':
            llfuse.notify_store(self.hello_inode, offset=0,
                                data=self.hello_data)
        else:
            raise FUSEError(errno.EINVAL)

def run_fs(mountpoint, cross_process):
    # Logging (note that we run in a new process, so we can't
    # rely on direct log capture and instead print to stdout)
    root_logger = logging.getLogger()
    formatter = logging.Formatter('%(asctime)s.%(msecs)03d %(levelname)s '
                                  '%(funcName)s(%(threadName)s): %(message)s',
                                   datefmt="%M:%S")
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(logging.DEBUG)
    handler.setFormatter(formatter)
    root_logger.addHandler(handler)
    root_logger.setLevel(logging.DEBUG)

    testfs = Fs(cross_process)
    fuse_options = set(llfuse.default_options)
    fuse_options.add('fsname=llfuse_testfs')
    llfuse.init(testfs, mountpoint, fuse_options)
    try:
        llfuse.main(workers=1)
    finally:
        llfuse.close()
