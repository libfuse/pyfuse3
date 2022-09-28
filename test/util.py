#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
util.py - Utility functions for pyfuse3 unit tests.

Copyright © 2015 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

import os
import platform
import pytest
import shutil
import stat
import subprocess
import time

def fuse_test_marker():
    '''Return a pytest.marker that indicates FUSE availability

    If system/user/environment does not support FUSE, return
    a `pytest.mark.skip` object with more details. If FUSE is
    supported, return `pytest.mark.uses_fuse()`.
    '''

    if platform.system() == 'Darwin':
        # No working autodetection, just assume it will work.
        return
    skip = lambda x: pytest.mark.skip(reason=x)

    fusermount_path = shutil.which('fusermount')
    if fusermount_path is None:
        return skip("Can't find fusermount executable")

    if not os.path.exists('/dev/fuse'):
        return skip("FUSE kernel module does not seem to be loaded")

    if os.getuid() == 0:
        return pytest.mark.uses_fuse()

    mode = os.stat(fusermount_path).st_mode
    if mode & stat.S_ISUID == 0:
        return skip('fusermount executable not setuid, and we are not root.')

    try:
        fd = os.open('/dev/fuse', os.O_RDWR)
    except OSError as exc:
        return skip('Unable to open /dev/fuse: %s' % exc.strerror)
    else:
        os.close(fd)

    return pytest.mark.uses_fuse()

def exitcode(process):
    if isinstance(process, subprocess.Popen):
        return process.poll()
    else:
        if process.is_alive():
            return None
        else:
            return process.exitcode

def wait_for(callable, timeout=10, interval=0.1):
    '''Wait until *callable* returns something True and return it

    If *timeout* expires, return None
    '''

    waited = 0
    while True:
        ret = callable()
        if ret:
            return ret
        if waited > timeout:
            return None
        waited += interval
        time.sleep(interval)

def wait_for_mount(mount_process, mnt_dir):
    elapsed = 0
    while elapsed < 30:
        if os.path.ismount(mnt_dir):
            return True
        if exitcode(mount_process) is not None:
            pytest.fail('file system process terminated prematurely')
        time.sleep(0.1)
        elapsed += 0.1
    pytest.fail("mountpoint failed to come up")

def cleanup(mount_process, mnt_dir):
    if platform.system() == 'Darwin':
        subprocess.call(['umount', '-l', mnt_dir], stdout=subprocess.DEVNULL,
                        stderr=subprocess.STDOUT)
    else:
        subprocess.call(['fusermount', '-z', '-u', mnt_dir], stdout=subprocess.DEVNULL,
                        stderr=subprocess.STDOUT)

    mount_process.terminate()
    if isinstance(mount_process, subprocess.Popen):
        try:
            mount_process.wait(1)
        except subprocess.TimeoutExpired:
            mount_process.kill()
    else:
        mount_process.join(5)
        if mount_process.exitcode is None:
            mount_process.kill()


def umount(mount_process, mnt_dir):
    if platform.system() == 'Darwin':
        subprocess.check_call(['umount', '-l', mnt_dir])
    else:
        subprocess.check_call(['fusermount', '-z', '-u', mnt_dir])
    assert not os.path.ismount(mnt_dir)

    if isinstance(mount_process, subprocess.Popen):
        try:
            code = mount_process.wait(5)
            if code == 0:
                return
            pytest.fail('file system process terminated with code %s' % (code,))
        except subprocess.TimeoutExpired:
            mount_process.terminate()
            try:
                mount_process.wait(1)
            except subprocess.TimeoutExpired:
                mount_process.kill()
    else:
        mount_process.join(5)
        code = mount_process.exitcode
        if code == 0:
            return
        elif code is None:
            mount_process.terminate()
            mount_process.join(1)
        else:
            pytest.fail('file system process terminated with code %s' % (code,))

    pytest.fail('mount process did not terminate')
