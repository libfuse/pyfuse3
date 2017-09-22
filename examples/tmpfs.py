#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
tmpfs.py - Example file system for Python-LLFUSE.

This file system stores all data in memory. It is compatible with both Python
2.x and 3.x.

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
'''

from __future__ import division, print_function, absolute_import

import os
import sys

# If we are running from the Python-LLFUSE source directory, try
# to load the module from there first.
basedir = os.path.abspath(os.path.join(os.path.dirname(sys.argv[0]), '..'))
if (os.path.exists(os.path.join(basedir, 'setup.py')) and
    os.path.exists(os.path.join(basedir, 'src', 'llfuse.pyx'))):
    sys.path.insert(0, os.path.join(basedir, 'src'))

import llfuse
import errno
import stat
from time import time
import sqlite3
import logging
from collections import defaultdict
from llfuse import FUSEError
from argparse import ArgumentParser

try:
    import faulthandler
except ImportError:
    pass
else:
    faulthandler.enable()

log = logging.getLogger()

# For Python 2 + 3 compatibility
if sys.version_info[0] == 2:
    def next(it):
        return it.next()
else:
    buffer = memoryview

class Operations(llfuse.Operations):
    '''An example filesystem that stores all data in memory

    This is a very simple implementation with terrible performance.
    Don't try to store significant amounts of data. Also, there are
    some other flaws that have not been fixed to keep the code easier
    to understand:

    * atime, mtime and ctime are not updated
    * generation numbers are not supported
    '''


    def __init__(self):
        super(Operations, self).__init__()
        self.db = sqlite3.connect(':memory:')
        self.db.text_factory = str
        self.db.row_factory = sqlite3.Row
        self.cursor = self.db.cursor()
        self.inode_open_count = defaultdict(int)
        self.init_tables()

    def init_tables(self):
        '''Initialize file system tables'''

        self.cursor.execute("""
        CREATE TABLE inodes (
            id        INTEGER PRIMARY KEY,
            uid       INT NOT NULL,
            gid       INT NOT NULL,
            mode      INT NOT NULL,
            mtime_ns  INT NOT NULL,
            atime_ns  INT NOT NULL,
            ctime_ns  INT NOT NULL,
            target    BLOB(256) ,
            size      INT NOT NULL DEFAULT 0,
            rdev      INT NOT NULL DEFAULT 0,
            data      BLOB
        )
        """)

        self.cursor.execute("""
        CREATE TABLE contents (
            rowid     INTEGER PRIMARY KEY AUTOINCREMENT,
            name      BLOB(256) NOT NULL,
            inode     INT NOT NULL REFERENCES inodes(id),
            parent_inode INT NOT NULL REFERENCES inodes(id),

            UNIQUE (name, parent_inode)
        )""")

        # Insert root directory
        now_ns = int(time() * 1e9)
        self.cursor.execute("INSERT INTO inodes (id,mode,uid,gid,mtime_ns,atime_ns,ctime_ns) "
                            "VALUES (?,?,?,?,?,?,?)",
                            (llfuse.ROOT_INODE, stat.S_IFDIR | stat.S_IRUSR | stat.S_IWUSR
                              | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH
                              | stat.S_IXOTH, os.getuid(), os.getgid(), now_ns, now_ns, now_ns))
        self.cursor.execute("INSERT INTO contents (name, parent_inode, inode) VALUES (?,?,?)",
                            (b'..', llfuse.ROOT_INODE, llfuse.ROOT_INODE))


    def get_row(self, *a, **kw):
        self.cursor.execute(*a, **kw)
        try:
            row = next(self.cursor)
        except StopIteration:
            raise NoSuchRowError()
        try:
            next(self.cursor)
        except StopIteration:
            pass
        else:
            raise NoUniqueValueError()

        return row

    def lookup(self, inode_p, name, ctx=None):
        if name == '.':
            inode = inode_p
        elif name == '..':
            inode = self.get_row("SELECT * FROM contents WHERE inode=?",
                                 (inode_p,))['parent_inode']
        else:
            try:
                inode = self.get_row("SELECT * FROM contents WHERE name=? AND parent_inode=?",
                                     (name, inode_p))['inode']
            except NoSuchRowError:
                raise(llfuse.FUSEError(errno.ENOENT))

        return self.getattr(inode, ctx)


    def getattr(self, inode, ctx=None):
        row = self.get_row('SELECT * FROM inodes WHERE id=?', (inode,))

        entry = llfuse.EntryAttributes()
        entry.st_ino = inode
        entry.generation = 0
        entry.entry_timeout = 300
        entry.attr_timeout = 300
        entry.st_mode = row['mode']
        entry.st_nlink = self.get_row("SELECT COUNT(inode) FROM contents WHERE inode=?",
                                     (inode,))[0]
        entry.st_uid = row['uid']
        entry.st_gid = row['gid']
        entry.st_rdev = row['rdev']
        entry.st_size = row['size']

        entry.st_blksize = 512
        entry.st_blocks = 1
        entry.st_atime_ns = row['atime_ns']
        entry.st_mtime_ns = row['mtime_ns']
        entry.st_ctime_ns = row['ctime_ns']

        return entry

    def readlink(self, inode, ctx):
        return self.get_row('SELECT * FROM inodes WHERE id=?', (inode,))['target']

    def opendir(self, inode, ctx):
        return inode

    def readdir(self, inode, off):
        if off == 0:
            off = -1

        cursor2 = self.db.cursor()
        cursor2.execute("SELECT * FROM contents WHERE parent_inode=? "
                        'AND rowid > ? ORDER BY rowid', (inode, off))

        for row in cursor2:
            yield (row['name'], self.getattr(row['inode']), row['rowid'])

    def unlink(self, inode_p, name,ctx):
        entry = self.lookup(inode_p, name)

        if stat.S_ISDIR(entry.st_mode):
            raise llfuse.FUSEError(errno.EISDIR)

        self._remove(inode_p, name, entry)

    def rmdir(self, inode_p, name, ctx):
        entry = self.lookup(inode_p, name)

        if not stat.S_ISDIR(entry.st_mode):
            raise llfuse.FUSEError(errno.ENOTDIR)

        self._remove(inode_p, name, entry)

    def _remove(self, inode_p, name, entry):
        if self.get_row("SELECT COUNT(inode) FROM contents WHERE parent_inode=?",
                        (entry.st_ino,))[0] > 0:
            raise llfuse.FUSEError(errno.ENOTEMPTY)

        self.cursor.execute("DELETE FROM contents WHERE name=? AND parent_inode=?",
                        (name, inode_p))

        if entry.st_nlink == 1 and entry.st_ino not in self.inode_open_count:
            self.cursor.execute("DELETE FROM inodes WHERE id=?", (entry.st_ino,))

    def symlink(self, inode_p, name, target, ctx):
        mode = (stat.S_IFLNK | stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                stat.S_IRGRP | stat.S_IWGRP | stat.S_IXGRP |
                stat.S_IROTH | stat.S_IWOTH | stat.S_IXOTH)
        return self._create(inode_p, name, mode, ctx, target=target)

    def rename(self, inode_p_old, name_old, inode_p_new, name_new, ctx):
        entry_old = self.lookup(inode_p_old, name_old)

        try:
            entry_new = self.lookup(inode_p_new, name_new)
        except llfuse.FUSEError as exc:
            if exc.errno != errno.ENOENT:
                raise
            target_exists = False
        else:
            target_exists = True

        if target_exists:
            self._replace(inode_p_old, name_old, inode_p_new, name_new,
                          entry_old, entry_new)
        else:
            self.cursor.execute("UPDATE contents SET name=?, parent_inode=? WHERE name=? "
                                "AND parent_inode=?", (name_new, inode_p_new,
                                                       name_old, inode_p_old))

    def _replace(self, inode_p_old, name_old, inode_p_new, name_new,
                 entry_old, entry_new):

        if self.get_row("SELECT COUNT(inode) FROM contents WHERE parent_inode=?",
                        (entry_new.st_ino,))[0] > 0:
            raise llfuse.FUSEError(errno.ENOTEMPTY)

        self.cursor.execute("UPDATE contents SET inode=? WHERE name=? AND parent_inode=?",
                            (entry_old.st_ino, name_new, inode_p_new))
        self.db.execute('DELETE FROM contents WHERE name=? AND parent_inode=?',
                        (name_old, inode_p_old))

        if entry_new.st_nlink == 1 and entry_new.st_ino not in self.inode_open_count:
            self.cursor.execute("DELETE FROM inodes WHERE id=?", (entry_new.st_ino,))


    def link(self, inode, new_inode_p, new_name, ctx):
        entry_p = self.getattr(new_inode_p)
        if entry_p.st_nlink == 0:
            log.warn('Attempted to create entry %s with unlinked parent %d',
                     new_name, new_inode_p)
            raise FUSEError(errno.EINVAL)

        self.cursor.execute("INSERT INTO contents (name, inode, parent_inode) VALUES(?,?,?)",
                            (new_name, inode, new_inode_p))

        return self.getattr(inode)

    def setattr(self, inode, attr, fields, fh, ctx):

        if fields.update_size:
            data = self.get_row('SELECT data FROM inodes WHERE id=?', (inode,))[0]
            if data is None:
                data = b''
            if len(data) < attr.st_size:
                data = data + b'\0' * (attr.st_size - len(data))
            else:
                data = data[:attr.st_size]
            self.cursor.execute('UPDATE inodes SET data=?, size=? WHERE id=?',
                                (buffer(data), attr.st_size, inode))
        if fields.update_mode:
            self.cursor.execute('UPDATE inodes SET mode=? WHERE id=?',
                                (attr.st_mode, inode))

        if fields.update_uid:
            self.cursor.execute('UPDATE inodes SET uid=? WHERE id=?',
                                (attr.st_uid, inode))

        if fields.update_gid:
            self.cursor.execute('UPDATE inodes SET gid=? WHERE id=?',
                                (attr.st_gid, inode))

        if fields.update_atime:
            self.cursor.execute('UPDATE inodes SET atime_ns=? WHERE id=?',
                                (attr.st_atime_ns, inode))

        if fields.update_mtime:
            self.cursor.execute('UPDATE inodes SET mtime_ns=? WHERE id=?',
                                (attr.st_mtime_ns, inode))

        return self.getattr(inode)

    def mknod(self, inode_p, name, mode, rdev, ctx):
        return self._create(inode_p, name, mode, ctx, rdev=rdev)

    def mkdir(self, inode_p, name, mode, ctx):
        return self._create(inode_p, name, mode, ctx)

    def statfs(self, ctx):
        stat_ = llfuse.StatvfsData()

        stat_.f_bsize = 512
        stat_.f_frsize = 512

        size = self.get_row('SELECT SUM(size) FROM inodes')[0]
        stat_.f_blocks = size // stat_.f_frsize
        stat_.f_bfree = max(size // stat_.f_frsize, 1024)
        stat_.f_bavail = stat_.f_bfree

        inodes = self.get_row('SELECT COUNT(id) FROM inodes')[0]
        stat_.f_files = inodes
        stat_.f_ffree = max(inodes , 100)
        stat_.f_favail = stat_.f_ffree

        return stat_

    def open(self, inode, flags, ctx):
        # Yeah, unused arguments
        #pylint: disable=W0613
        self.inode_open_count[inode] += 1

        # Use inodes as a file handles
        return inode

    def access(self, inode, mode, ctx):
        # Yeah, could be a function and has unused arguments
        #pylint: disable=R0201,W0613
        return True

    def create(self, inode_parent, name, mode, flags, ctx):
        #pylint: disable=W0612
        entry = self._create(inode_parent, name, mode, ctx)
        self.inode_open_count[entry.st_ino] += 1
        return (entry.st_ino, entry)

    def _create(self, inode_p, name, mode, ctx, rdev=0, target=None):
        if self.getattr(inode_p).st_nlink == 0:
            log.warn('Attempted to create entry %s with unlinked parent %d',
                     name, inode_p)
            raise FUSEError(errno.EINVAL)

        now_ns = int(time() * 1e9)
        self.cursor.execute('INSERT INTO inodes (uid, gid, mode, mtime_ns, atime_ns, '
                            'ctime_ns, target, rdev) VALUES(?, ?, ?, ?, ?, ?, ?, ?)',
                            (ctx.uid, ctx.gid, mode, now_ns, now_ns, now_ns, target, rdev))

        inode = self.cursor.lastrowid
        self.db.execute("INSERT INTO contents(name, inode, parent_inode) VALUES(?,?,?)",
                        (name, inode, inode_p))
        return self.getattr(inode)

    def read(self, fh, offset, length):
        data = self.get_row('SELECT data FROM inodes WHERE id=?', (fh,))[0]
        if data is None:
            data = b''
        return data[offset:offset+length]

    def write(self, fh, offset, buf):
        data = self.get_row('SELECT data FROM inodes WHERE id=?', (fh,))[0]
        if data is None:
            data = b''
        data = data[:offset] + buf + data[offset+len(buf):]

        self.cursor.execute('UPDATE inodes SET data=?, size=? WHERE id=?',
                            (buffer(data), len(data), fh))
        return len(buf)

    def release(self, fh):
        self.inode_open_count[fh] -= 1

        if self.inode_open_count[fh] == 0:
            del self.inode_open_count[fh]
            if self.getattr(fh).st_nlink == 0:
                self.cursor.execute("DELETE FROM inodes WHERE id=?", (fh,))

class NoUniqueValueError(Exception):
    def __str__(self):
        return 'Query generated more than 1 result row'


class NoSuchRowError(Exception):
    def __str__(self):
        return 'Query produced 0 result rows'

def init_logging(debug=False):
    formatter = logging.Formatter('%(asctime)s.%(msecs)03d %(threadName)s: '
                                  '[%(name)s] %(message)s', datefmt="%Y-%m-%d %H:%M:%S")
    handler = logging.StreamHandler()
    handler.setFormatter(formatter)
    root_logger = logging.getLogger()
    if debug:
        handler.setLevel(logging.DEBUG)
        root_logger.setLevel(logging.DEBUG)
    else:
        handler.setLevel(logging.INFO)
        root_logger.setLevel(logging.INFO)
    root_logger.addHandler(handler)

def parse_args():
    '''Parse command line'''

    parser = ArgumentParser()

    parser.add_argument('mountpoint', type=str,
                        help='Where to mount the file system')
    parser.add_argument('--debug', action='store_true', default=False,
                        help='Enable debugging output')
    parser.add_argument('--debug-fuse', action='store_true', default=False,
                        help='Enable FUSE debugging output')

    return parser.parse_args()


if __name__ == '__main__':

    options = parse_args()
    init_logging(options.debug)
    operations = Operations()

    fuse_options = set(llfuse.default_options)
    fuse_options.add('fsname=tmpfs')
    fuse_options.discard('default_permissions')
    if options.debug_fuse:
        fuse_options.add('debug')
    llfuse.init(operations, options.mountpoint, fuse_options)

    # sqlite3 does not support multithreading
    try:
        llfuse.main(workers=1)
    except:
        llfuse.close(unmount=False)
        raise

    llfuse.close()
