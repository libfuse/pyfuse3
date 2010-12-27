#!/usr/bin/env python
'''
llfuse_example.py

Example file system that uses python-llfuse.

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of python-llfuse (http://python-llfuse.googlecode.com).
python-llfuse can be distributed under the terms of the GNU LGPL.
'''

from __future__ import division, print_function, absolute_import

import os
import sys

# We are running from the llfuse source directory, make sure
# that we use modules from this directory
basedir = os.path.abspath(os.path.join(os.path.dirname(sys.argv[0]), '..'))
if (os.path.exists(os.path.join(basedir, 'setup.py')) and
    os.path.exists(os.path.join(basedir, 'src', 'llfuse.so'))):
    sys.path = [os.path.join(basedir, 'src')] + sys.path
    
    
import llfuse
import errno
import stat
from time import time
import sqlite3
import logging
from collections import defaultdict
from llfuse import FUSEError

log = logging.getLogger()

class Operations(llfuse.Operations):
    '''An example filesystem that stores all data in memory
    
    This is a very simple implementation with terrible
    performance. Don't try to store significant amounts of
    data. Also, there are some other flaws that have not been
    fixed to keep the code easier to understand:
    
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
            mtime     REAL NOT NULL,
            atime     REAL NOT NULL,
            ctime     REAL NOT NULL,
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
        self.cursor.execute("INSERT INTO inodes (id,mode,uid,gid,mtime,atime,ctime) "
                            "VALUES (?,?,?,?,?,?,?)",
                            (llfuse.ROOT_INODE, stat.S_IFDIR | stat.S_IRUSR | stat.S_IWUSR
                              | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH 
                              | stat.S_IXOTH, os.getuid(), os.getgid(), time(), 
                              time(), time()))
        self.cursor.execute("INSERT INTO contents (name, parent_inode, inode) VALUES (?,?,?)",
                            (b'..', llfuse.ROOT_INODE, llfuse.ROOT_INODE))
        
                
    def get_row(self, *a, **kw):
        self.cursor.execute(*a, **kw) 
        try:
            row = self.cursor.next()
        except StopIteration:
            raise NoSuchRowError()
        try:
            self.cursor.next()
        except StopIteration:
            pass
        else:
            raise NoUniqueValueError()

        return row
                    
    def lookup(self, inode_p, name):
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
        
        return self.getattr(inode)
        

    def getattr(self, inode):
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
        entry.st_atime = row['atime']                          
        entry.st_mtime = row['mtime']
        entry.st_ctime = row['ctime']
        
        return entry

    def readlink(self, inode):
        return self.get_row('SELECT * FROM inodes WHERE id=?', (inode,))['target']
    
    def opendir(self, inode):
        return inode

    def readdir(self, inode, off):
        if off == 0:
            off = -1
            
        cursor2 = self.db.cursor()
        cursor2.execute("SELECT * FROM contents WHERE parent_inode=? "
                        'AND rowid > ? ORDER BY rowid', (inode, off))
        
        for row in cursor2:
            yield (row['name'], self.getattr(row['inode']), row['rowid'])

    def unlink(self, inode_p, name):
        entry = self.lookup(inode_p, name)

        if stat.S_ISDIR(entry.st_mode):
            raise llfuse.FUSEError(errno.EISDIR)

        self._remove(inode_p, name, entry)

    def rmdir(self, inode_p, name):
        entry = self.lookup(inode_p, name)

        if not stat.S_ISDIR(entry.st_mode):
            raise llfuse.FUSEError(errno.ENOTDIR)

        self._remove(inode_p, name, entry)

    def _remove(self, inode_p, name, entry):
        if self.get_row("SELECT COUNT(inode) FROM contents WHERE parent_inode=?", 
                        (entry.st_ino))[0] > 0:
            raise llfuse.FUSEError(errno.ENOTEMPTY)

        self.cur.execute("DELETE FROM contents WHERE name=? AND parent_inode=?",
                        (name, inode_p))
        
        if entry.st_nlink == 1 and entry.st_ino not in self.inode_open_count:
            self.cur.execute("DELETE FROM inodes WHERE id=?", (entry.st_ino,))

    def symlink(self, inode_p, name, target, ctx):
        mode = (stat.S_IFLNK | stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR | 
                stat.S_IRGRP | stat.S_IWGRP | stat.S_IXGRP | 
                stat.S_IROTH | stat.S_IWOTH | stat.S_IXOTH)
        return self._create(inode_p, name, mode, ctx, target=target)

    def rename(self, inode_p_old, name_old, inode_p_new, name_new):     
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
                        (entry_new.st_ino))[0] > 0:
            raise llfuse.FUSEError(errno.ENOTEMPTY)
   
        self.cursor.execute("UPDATE contents SET inode=? WHERE name=? AND parent_inode=?",
                            (entry_old.st_ino, name_new, inode_p_new))
        self.db.execute('DELETE FROM contents WHERE name=? AND parent_inode=?',
                        (name_old, inode_p_old))

        if entry_new.st_nlink == 1 and entry_new.st_ino not in self.inode_open_count:
            self.cur.execute("DELETE FROM inodes WHERE id=?", (entry_new.st_ino,))


    def link(self, inode, new_inode_p, new_name):
        entry_p = self.getattr(new_inode_p)
        if entry_p.st_nlink == 0:
            log.warn('Attempted to create entry %s with unlinked parent %d',
                     new_name, new_inode_p)
            raise FUSEError(errno.EINVAL)

        self.cursor.execute("INSERT INTO contents (name, inode, parent_inode) VALUES(?,?,?)",
                            (new_name, inode, new_inode_p))

        return self.getattr(inode)

    def setattr(self, inode, attr):

        if attr.st_size is not None:
            data = self.get_row('SELECT data FROM inodes WHERE id=?', (inode,))[0]
            if data is None:
                data = ''
            if len(data) < attr.st_size:
                data = data + '\0' * (attr.st_size - len(data))
            else:
                data = data[:attr.st_size]
            self.cursor.execute('UPDATE inodes SET data=?, size=? WHERE id=?',
                                (buffer(data), attr.st_size, inode))
        if attr.st_mode is not None:
            self.cursor.execute('UPDATE inodes SET mode=? WHERE id=?',
                                (attr.st_mode, inode))

        if attr.st_uid is not None:
            self.cursor.execute('UPDATE inodes SET uid=? WHERE id=?',
                                (attr.st_uid, inode))

        if attr.st_gid is not None:
            self.cursor.execute('UPDATE inodes SET gid=? WHERE id=?',
                                (attr.st_gid, inode))

        if attr.st_rdev is not None:
            self.cursor.execute('UPDATE inodes SET rdev=? WHERE id=?',
                                (attr.st_rdev, inode))

        if attr.st_atime is not None:
            self.cursor.execute('UPDATE inodes SET atime=? WHERE id=?',
                                (attr.st_atime, inode))

        if attr.st_mtime is not None:
            self.cursor.execute('UPDATE inodes SET mtime=? WHERE id=?',
                                (attr.st_mtime, inode))

        if attr.st_ctime is not None:
            self.cursor.execute('UPDATE inodes SET ctime=? WHERE id=?',
                                (attr.st_ctime, inode))

        return self.getattr(inode)

    def mknod(self, inode_p, name, mode, rdev, ctx):
        return self._create(inode_p, name, mode, ctx, rdev=rdev)

    def mkdir(self, inode_p, name, mode, ctx):
        return self._create(inode_p, name, mode, ctx)

    def statfs(self):
        stat_ = llfuse.StatvfsData()

        stat_.f_bsize = 512
        stat_.f_frsize = 512

        size = self.get_row('SELECT SUM(size) FROM inodes')[0]
        stat_.f_blocks = size // stat_.f_frsize
        stat_.f_bfree = max(size // stat_.f_frsize, 1024)
        stat_.f_bavail = stat_["f_bfree"]

        inodes = self.get_row('SELECT COUNT(id) FROM inodes')[0]
        stat_.f_files = inodes
        stat_.f_ffree = max(inodes , 100)
        stat_.f_favail = stat_.f_ffree

        return stat_

    def open(self, inode, flags):
        # Yeah, unused arguments
        #pylint: disable=W0613
        self.inode_open_count[inode] += 1
        
        # Use inodes as a file handles
        return inode

    def access(self, inode, mode, ctx):
        # Yeah, could be a function and has unused arguments
        #pylint: disable=R0201,W0613
        return True

    def create(self, inode_parent, name, mode, ctx):
        entry = self._create(inode_parent, name, mode, ctx)
        self.inode_open_count[entry.st_ino] += 1
        return (entry.st_ino, entry)

    def _create(self, inode_p, name, mode, ctx, rdev=0, target=None):             
        if self.getattr(inode_p).st_nlink == 0:
            log.warn('Attempted to create entry %s with unlinked parent %d',
                     name, inode_p)
            raise FUSEError(errno.EINVAL)

        self.cursor.execute('INSERT INTO inodes (uid, gid, mode, mtime, atime, '
                            'ctime, target, rdev) VALUES(?, ?, ?, ?, ?, ?, ?, ?)',
                            (ctx.uid, ctx.gid, mode, time(), time(), time(), target, rdev))

        inode = self.cursor.lastrowid
        self.db.execute("INSERT INTO contents(name, inode, parent_inode) VALUES(?,?,?)",
                        (name, inode, inode_p))
        return self.getattr(inode)


    def read(self, fh, offset, length):
        data = self.get_row('SELECT data FROM inodes WHERE id=?', (fh,))[0]
        if data is None:
            data = ''
        return data[offset:offset+length]

                
    def write(self, fh, offset, buf):
        data = self.get_row('SELECT data FROM inodes WHERE id=?', (fh,))[0]
        if data is None:
            data = ''
        data = data[:offset] + buf + data[offset+len(buf):]
        
        self.cursor.execute('UPDATE inodes SET data=?, size=? WHERE id=?',
                            (buffer(data), len(data), fh))
        return len(buf)
   
    def release(self, fh):
        self.inode_open_count[fh] -= 1

        if self.inode_open_count[fh] == 0:
            del self.inode_open_count[fh]
            if self.getattr(fh).st_nlink == 0:
                self.cur.execute("DELETE FROM inodes WHERE id=?", (fh,))

class NoUniqueValueError(Exception):
    def __str__(self):
        return 'Query generated more than 1 result row'
    
    
class NoSuchRowError(Exception):
    def __str__(self):
        return 'Query produced 0 result rows'
    
def init_logging():
    formatter = logging.Formatter('%(message)s') 
    handler = logging.StreamHandler()
    handler.setFormatter(formatter)
    handler.setLevel(logging.INFO)
    log.setLevel(logging.INFO)    
    log.addHandler(handler)    
        
if __name__ == '__main__':
    
    if len(sys.argv) != 2:
        raise SystemExit('Usage: %s <mountpoint>' % sys.argv[0])
    
    init_logging()
    mountpoint = sys.argv[1]
    operations = Operations()
    
    llfuse.init(operations, mountpoint, 
                [  b'fsname=llfuse_xmp', b"nonempty" ])
    
    # sqlite3 does not support multithreading
    llfuse.main(single=True)
    llfuse.close()
    
