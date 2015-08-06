#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
test_examples.py - Unit tests for Python-LLFUSE.

Copyright © 2015 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
'''

if __name__ == '__main__':
    import pytest
    import sys
    sys.exit(pytest.main([__file__] + sys.argv[1:]))

import subprocess
import os
import sys
import time
import pytest
import stat
import shutil
import platform
import filecmp
import errno

basename = os.path.join(os.path.dirname(__file__), '..')
TEST_FILE = __file__

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
skip_if_no_fuse()


def wait_for_mount(mount_process, mnt_dir):
    elapsed = 0
    while elapsed < 30:
        if os.path.ismount(mnt_dir):
            return True
        if mount_process.poll() is not None:
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
        if mount_process.poll() is not None:
            if mount_process.returncode == 0:
                return
            pytest.fail('file system process terminated with code %d' %
                        mount_process.exitcode)
        time.sleep(0.1)
        elapsed += 0.1
    pytest.fail('mount process did not terminate')

def name_generator(__ctr=[0]):
    __ctr[0] += 1
    return 'testfile_%d' % __ctr[0]

def test_lltest(tmpdir):
    mnt_dir = str(tmpdir)
    cmdline = [sys.executable,
               os.path.join(basename, 'examples', 'lltest.py'),
               mnt_dir ]
    mount_process = subprocess.Popen(cmdline, stdin=subprocess.DEVNULL,
                                     universal_newlines=True)
    try:
        wait_for_mount(mount_process, mnt_dir)
        assert os.listdir(mnt_dir) == [ 'message' ]
        filename = os.path.join(mnt_dir, 'message')
        with open(filename, 'r') as fh:
            assert fh.read() == 'hello world\n'
        with pytest.raises(IOError) as exc_info:
            open(filename, 'r+')
        assert exc_info.value.errno == errno.EPERM
        with pytest.raises(IOError) as exc_info:
            open(filename + 'does-not-exist', 'r+')
        assert exc_info.value.errno == errno.ENOENT
    except:
        cleanup(mnt_dir)
        raise
    else:
        umount(mount_process, mnt_dir)

def test_tmpfs(tmpdir):
    mnt_dir = str(tmpdir)
    cmdline = [sys.executable,
               os.path.join(basename, 'examples', 'tmpfs.py'),
               mnt_dir ]
    mount_process = subprocess.Popen(cmdline, stdin=subprocess.DEVNULL,
                                     universal_newlines=True)
    try:
        wait_for_mount(mount_process, mnt_dir)
        tst_write(mnt_dir)
        tst_mkdir(mnt_dir)
        tst_symlink(mnt_dir)
        tst_mknod(mnt_dir)
        tst_chown(mnt_dir)
        tst_utimens(mnt_dir)
        tst_link(mnt_dir)
        tst_readdir(mnt_dir)
        tst_statvfs(mnt_dir)
        tst_truncate(mnt_dir)
    except:
        cleanup(mnt_dir)
        raise
    else:
        umount(mount_process, mnt_dir)

@pytest.mark.skipif(sys.version_info < (3,3),
                    reason="requires python3.3")
def test_passthroughfs(tmpdir):
    mnt_dir = str(tmpdir.mkdir('mnt'))
    src_dir = str(tmpdir.mkdir('src'))
    cmdline = [sys.executable,
               os.path.join(basename, 'examples', 'passthroughfs.py'),
               src_dir, mnt_dir ]
    mount_process = subprocess.Popen(cmdline, stdin=subprocess.DEVNULL,
                                     universal_newlines=True)
    try:
        wait_for_mount(mount_process, mnt_dir)
        tst_write(mnt_dir)
        tst_mkdir(mnt_dir)
        tst_symlink(mnt_dir)
        tst_mknod(mnt_dir)
        if os.getuid() == 0:
            tst_chown(mnt_dir)
        # Underlying fs may not have full nanosecond resolution
        tst_utimens(mnt_dir, ns_tol=1000)
        tst_link(mnt_dir)
        tst_readdir(mnt_dir)
        tst_statvfs(mnt_dir)
        tst_truncate(mnt_dir)
        tst_passthrough(src_dir, mnt_dir)
    except:
        cleanup(mnt_dir)
        raise
    else:
        umount(mount_process, mnt_dir)

def checked_unlink(filename, path, isdir=False):
    fullname = os.path.join(path, filename)
    if isdir:
        os.rmdir(fullname)
    else:
        os.unlink(fullname)
    with pytest.raises(OSError) as exc_info:
        os.stat(fullname)
    assert exc_info.value.errno == errno.ENOENT
    assert filename not in os.listdir(path)

def tst_mkdir(mnt_dir):
    dirname = name_generator()
    fullname = mnt_dir + "/" + dirname
    os.mkdir(fullname)
    fstat = os.stat(fullname)
    assert stat.S_ISDIR(fstat.st_mode)
    assert os.listdir(fullname) ==  []
    assert fstat.st_nlink in (1,2)
    assert dirname in os.listdir(mnt_dir)
    checked_unlink(dirname, mnt_dir, isdir=True)

def tst_symlink(mnt_dir):
    linkname = name_generator()
    fullname = mnt_dir + "/" + linkname
    os.symlink("/imaginary/dest", fullname)
    fstat = os.lstat(fullname)
    assert stat.S_ISLNK(fstat.st_mode)
    assert os.readlink(fullname) == "/imaginary/dest"
    assert fstat.st_nlink == 1
    assert linkname in os.listdir(mnt_dir)
    checked_unlink(linkname, mnt_dir)

def tst_mknod(mnt_dir):
    filename = os.path.join(mnt_dir, name_generator())
    shutil.copyfile(TEST_FILE, filename)
    fstat = os.lstat(filename)
    assert stat.S_ISREG(fstat.st_mode)
    assert fstat.st_nlink == 1
    assert os.path.basename(filename) in os.listdir(mnt_dir)
    assert filecmp.cmp(TEST_FILE, filename, False)
    checked_unlink(filename, mnt_dir)

def tst_chown(mnt_dir):
    filename = os.path.join(mnt_dir, name_generator())
    os.mkdir(filename)
    fstat = os.lstat(filename)
    uid = fstat.st_uid
    gid = fstat.st_gid

    uid_new = uid + 1
    os.chown(filename, uid_new, -1)
    fstat = os.lstat(filename)
    assert fstat.st_uid == uid_new
    assert fstat.st_gid == gid

    gid_new = gid + 1
    os.chown(filename, -1, gid_new)
    fstat = os.lstat(filename)
    assert fstat.st_uid == uid_new
    assert fstat.st_gid == gid_new

    checked_unlink(filename, mnt_dir, isdir=True)

def tst_write(mnt_dir):
    name = os.path.join(mnt_dir, name_generator())
    shutil.copyfile(TEST_FILE, name)
    assert filecmp.cmp(name, TEST_FILE, False)
    checked_unlink(name, mnt_dir)

def tst_statvfs(mnt_dir):
    os.statvfs(mnt_dir)

def tst_link(mnt_dir):
    name1 = os.path.join(mnt_dir, name_generator())
    name2 = os.path.join(mnt_dir, name_generator())
    shutil.copyfile(TEST_FILE, name1)
    assert filecmp.cmp(name1, TEST_FILE, False)
    os.link(name1, name2)

    fstat1 = os.lstat(name1)
    fstat2 = os.lstat(name2)

    assert fstat1 == fstat2
    assert fstat1.st_nlink == 2

    assert os.path.basename(name2) in os.listdir(mnt_dir)
    assert filecmp.cmp(name1, name2, False)
    os.unlink(name2)
    fstat1 = os.lstat(name1)
    assert fstat1.st_nlink == 1
    os.unlink(name1)

def tst_readdir(mnt_dir):
    dir_ = os.path.join(mnt_dir, name_generator())
    file_ = dir_ + "/" + name_generator()
    subdir = dir_ + "/" + name_generator()
    subfile = subdir + "/" + name_generator()

    os.mkdir(dir_)
    shutil.copyfile(TEST_FILE, file_)
    os.mkdir(subdir)
    shutil.copyfile(TEST_FILE, subfile)

    listdir_is = os.listdir(dir_)
    listdir_is.sort()
    listdir_should = [ os.path.basename(file_), os.path.basename(subdir) ]
    listdir_should.sort()
    assert listdir_is == listdir_should

    os.unlink(file_)
    os.unlink(subfile)
    os.rmdir(subdir)
    os.rmdir(dir_)

def tst_truncate(mnt_dir):
    filename = os.path.join(mnt_dir, name_generator())
    shutil.copyfile(TEST_FILE, filename)
    assert filecmp.cmp(filename, TEST_FILE, False)
    fstat = os.stat(filename)
    size = fstat.st_size
    fd = os.open(filename, os.O_RDWR)

    os.ftruncate(fd, size + 1024) # add > 1 block
    assert os.stat(filename).st_size == size + 1024

    os.ftruncate(fd, size - 1024) # Truncate > 1 block
    assert os.stat(filename).st_size == size - 1024

    os.close(fd)
    os.unlink(filename)

def tst_utimens(mnt_dir, ns_tol=0):
    filename = os.path.join(mnt_dir, name_generator())
    os.mkdir(filename)
    fstat = os.lstat(filename)

    atime = fstat.st_atime + 42.28
    mtime = fstat.st_mtime - 42.23
    if sys.version_info < (3,3):
        os.utime(filename, (atime, mtime))
    else:
        atime_ns = fstat.st_atime_ns + int(42.28*1e9)
        mtime_ns = fstat.st_mtime_ns - int(42.23*1e9)
        os.utime(filename, None, ns=(atime_ns, mtime_ns))

    fstat = os.lstat(filename)

    assert abs(fstat.st_atime - atime) < 1e-3
    assert abs(fstat.st_mtime - mtime) < 1e-3
    if sys.version_info >= (3,3):
        assert abs(fstat.st_atime_ns - atime_ns) <= ns_tol
        assert abs(fstat.st_mtime_ns - mtime_ns) <= ns_tol

    checked_unlink(filename, mnt_dir, isdir=True)

def tst_passthrough(src_dir, mnt_dir):
    name = name_generator()
    src_name = os.path.join(src_dir, name)
    mnt_name = os.path.join(src_dir, name)
    assert name not in os.listdir(src_dir)
    assert name not in os.listdir(mnt_dir)
    with open(src_name, 'w') as fh:
        fh.write('Hello, world')
    assert name in os.listdir(src_dir)
    assert name in os.listdir(mnt_dir)
    assert os.stat(src_name) == os.stat(mnt_name)

    name = name_generator()
    src_name = os.path.join(src_dir, name)
    mnt_name = os.path.join(src_dir, name)
    assert name not in os.listdir(src_dir)
    assert name not in os.listdir(mnt_dir)
    with open(mnt_name, 'w') as fh:
        fh.write('Hello, world')
    assert name in os.listdir(src_dir)
    assert name in os.listdir(mnt_dir)
    assert os.stat(src_name) == os.stat(mnt_name)
