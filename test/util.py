#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
util.py - Utility functions for Python-LLFUSE unit tests.

Copyright © 2015 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
'''

from __future__ import division, print_function, absolute_import

import platform
import subprocess
import pytest
import os
import stat
import time
import sys

# For Python 2 + 3 compatibility
if sys.version_info[0] == 2:
    subprocess.DEVNULL = open('/dev/null', 'w')

def skip_if_no_fuse():
    '''Skip test if system/user/environment does not support FUSE'''

    if platform.system() == 'Darwin':
        # No working autodetection, just assume it will work.
        return

    # Python 2.x: Popen is not a context manager...
    which = subprocess.Popen(['which', 'fusermount'], stdout=subprocess.PIPE,
                             universal_newlines=True)
    try:
        fusermount_path = which.communicate()[0].strip()
    finally:
        which.wait()

    if not fusermount_path or which.returncode != 0:
        pytest.skip("Can't find fusermount executable")

    if not os.path.exists('/dev/fuse'):
        pytest.skip("FUSE kernel module does not seem to be loaded")

    if os.getuid() == 0:
        return

    mode = os.stat(fusermount_path).st_mode
    if mode & stat.S_ISUID == 0:
        pytest.skip('fusermount executable not setuid, and we are not root.')

    try:
        fd = os.open('/dev/fuse', os.O_RDWR)
    except OSError as exc:
        pytest.skip('Unable to open /dev/fuse: %s' % exc.strerror)
    else:
        os.close(fd)

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

def cleanup(mnt_dir):
    if platform.system() == 'Darwin':
        subprocess.call(['umount', '-l', mnt_dir], stdout=subprocess.DEVNULL,
                        stderr=subprocess.STDOUT)
    else:
        subprocess.call(['fusermount', '-z', '-u', mnt_dir], stdout=subprocess.DEVNULL,
                        stderr=subprocess.STDOUT)

def umount(mount_process, mnt_dir):
    if platform.system() == 'Darwin':
        subprocess.check_call(['umount', '-l', mnt_dir])
    else:
        subprocess.check_call(['fusermount', '-z', '-u', mnt_dir])
    assert not os.path.ismount(mnt_dir)

    # Give mount process a little while to terminate. Popen.wait(timeout)
    # was only added in 3.3...
    elapsed = 0
    while elapsed < 30:
        code = exitcode(mount_process)
        if code is not None:
            if code == 0:
                return
            pytest.fail('file system process terminated with code %s' % (code,))
        time.sleep(0.1)
        elapsed += 0.1
    pytest.fail('mount process did not terminate')
