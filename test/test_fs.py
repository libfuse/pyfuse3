#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
test_fs.py - Unit tests for pyfuse3.

Copyright © 2015 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

import pytest
import sys

if __name__ == '__main__':
    sys.exit(pytest.main([__file__] + sys.argv[1:]))

import pyfuse3
from pyfuse3 import FUSEError
import multiprocessing
import os
import errno
import stat
import time
import logging
import trio
import threading
from util import fuse_test_marker, wait_for_mount, umount, cleanup

pytestmark = fuse_test_marker()

def get_mp():
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

    return mp


@pytest.fixture()
def testfs(tmpdir):
    mnt_dir = str(tmpdir)
    mp = get_mp()
    with mp.Manager() as mgr:
        cross_process = mgr.Namespace()
        mount_process = mp.Process(target=run_fs,
                                   args=(mnt_dir, cross_process))

        mount_process.start()
        try:
            wait_for_mount(mount_process, mnt_dir)
            yield (mnt_dir, cross_process)
        except:
            cleanup(mnt_process, mnt_dir)
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

    # Hardcoded sleeptimes - sorry! Needed because of the special semantics of
    # invalidate_entry()
    pyfuse3.setxattr(mnt_dir, 'command', b'forget_entry')
    time.sleep(1.1)
    os.stat(path)
    assert fs_state.lookup_called

def test_invalidate_inode(testfs):
    (mnt_dir, fs_state) = testfs
    with open(os.path.join(mnt_dir, 'message'), 'r') as fh:
        assert fh.read() == 'hello world\n'
        assert fs_state.read_called
        fs_state.read_called = False
        fh.seek(0)
        assert fh.read() == 'hello world\n'
        assert not fs_state.read_called

        pyfuse3.setxattr(mnt_dir, 'command', b'forget_inode')
        fh.seek(0)
        assert fh.read() == 'hello world\n'
        assert fs_state.read_called

def test_notify_store(testfs):
    (mnt_dir, fs_state) = testfs
    with open(os.path.join(mnt_dir, 'message'), 'r') as fh:
        pyfuse3.setxattr(mnt_dir, 'command', b'store')
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

def test_terminate(tmpdir):
    mnt_dir = str(tmpdir)
    mp = get_mp()
    with mp.Manager() as mgr:
        fs_state = mgr.Namespace()
        mount_process = mp.Process(target=run_fs,
                                   args=(mnt_dir, fs_state))

        mount_process.start()
        try:
            wait_for_mount(mount_process, mnt_dir)
            pyfuse3.setxattr(mnt_dir, 'command', b'terminate')
            mount_process.join(5)
            assert mount_process.exitcode is not None
        except:
            cleanup(mount_process, mnt_dir)
            raise


class Fs(pyfuse3.Operations):
    def __init__(self, cross_process):
        super(Fs, self).__init__()
        self.hello_name = b"message"
        self.hello_inode = pyfuse3.ROOT_INODE+1
        self.hello_data = b"hello world\n"
        self.status = cross_process
        self.lookup_cnt = 0
        self.status.getattr_called = False
        self.status.lookup_called = False
        self.status.read_called = False
        self.status.entry_timeout = 99999
        self.status.attr_timeout = 99999

    async def getattr(self, inode, ctx=None):
        entry = pyfuse3.EntryAttributes()
        if inode == pyfuse3.ROOT_INODE:
            entry.st_mode = (stat.S_IFDIR | 0o755)
            entry.st_size = 0
        elif inode == self.hello_inode:
            entry.st_mode = (stat.S_IFREG | 0o644)
            entry.st_size = len(self.hello_data)
        else:
            raise pyfuse3.FUSEError(errno.ENOENT)

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

    async def forget(self, inode_list):
        for (inode, cnt) in inode_list:
            if inode == self.hello_inode:
                self.lookup_cnt -= 1
                assert self.lookup_cnt >= 0
            else:
                assert inode == pyfuse3.ROOT_INODE

    async def lookup(self, parent_inode, name, ctx=None):
        if parent_inode != pyfuse3.ROOT_INODE or name != self.hello_name:
            raise pyfuse3.FUSEError(errno.ENOENT)
        self.lookup_cnt += 1
        self.status.lookup_called = True
        return await self.getattr(self.hello_inode)

    async def opendir(self, inode, ctx):
        if inode != pyfuse3.ROOT_INODE:
            raise pyfuse3.FUSEError(errno.ENOENT)
        return inode

    async def readdir(self, fh, off, token):
        assert fh == pyfuse3.ROOT_INODE
        if off == 0:
            pyfuse3.readdir_reply(
                token, self.hello_name, await self.getattr(self.hello_inode), 1)
        return

    async def open(self, inode, flags, ctx):
        if inode != self.hello_inode:
            raise pyfuse3.FUSEError(errno.ENOENT)
        if flags & os.O_RDWR or flags & os.O_WRONLY:
            raise pyfuse3.FUSEError(errno.EACCES)
        return pyfuse3.FileInfo(fh=inode)

    async def read(self, fh, off, size):
        assert fh == self.hello_inode
        self.status.read_called = True
        return self.hello_data[off:off+size]

    async def setxattr(self, inode, name, value, ctx):
        if inode != pyfuse3.ROOT_INODE or name != b'command':
            raise FUSEError(errno.ENOTSUP)

        if value == b'forget_entry':
            pyfuse3.invalidate_entry_async(pyfuse3.ROOT_INODE, self.hello_name)

            # Make sure that the request is pending before we return
            await trio.sleep(0.1)

        elif value == b'forget_inode':
            pyfuse3.invalidate_inode(self.hello_inode)

        elif value == b'store':
            pyfuse3.notify_store(self.hello_inode, offset=0,
                                 data=self.hello_data)

        elif value == b'terminate':
            pyfuse3.terminate()
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
    fuse_options = set(pyfuse3.default_options)
    fuse_options.add('fsname=pyfuse3_testfs')
    pyfuse3.init(testfs, mountpoint, fuse_options)
    try:
        trio.run(pyfuse3.main)
    finally:
        pyfuse3.close()
