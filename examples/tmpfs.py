#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
tmpfs.py - Example file system for pyfuse3.

This file system stores all data in memory.

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

import errno
import logging
import os
import sqlite3
import stat
from argparse import ArgumentParser, Namespace
from collections import defaultdict
from time import time
from typing import Any, cast

import trio

import pyfuse3
from pyfuse3 import (
    EntryAttributes,
    FileHandleT,
    FileInfo,
    FUSEError,
    InodeT,
    ReaddirToken,
    RequestContext,
    SetattrFields,
    StatvfsData,
)

try:
    import faulthandler
except ImportError:
    pass
else:
    faulthandler.enable()

log = logging.getLogger()


class Operations(pyfuse3.Operations):
    '''An example filesystem that stores all data in memory

    This is a very simple implementation with terrible performance.
    Don't try to store significant amounts of data. Also, there are
    some other flaws that have not been fixed to keep the code easier
    to understand:

    * atime, mtime and ctime are not updated
    * generation numbers are not supported
    * lookup counts are not maintained
    '''

    enable_writeback_cache = True

    def __init__(self) -> None:
        super(Operations, self).__init__()
        self.db: sqlite3.Connection = sqlite3.connect(':memory:')
        self.db.text_factory = str
        self.db.row_factory = sqlite3.Row
        self.cursor: sqlite3.Cursor = self.db.cursor()
        self.inode_open_count: defaultdict[InodeT, int] = defaultdict(int)
        self.init_tables()

    def init_tables(self) -> None:
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
        self.cursor.execute(
            "INSERT INTO inodes (id,mode,uid,gid,mtime_ns,atime_ns,ctime_ns) "
            "VALUES (?,?,?,?,?,?,?)",
            (
                pyfuse3.ROOT_INODE,
                stat.S_IFDIR
                | stat.S_IRUSR
                | stat.S_IWUSR
                | stat.S_IXUSR
                | stat.S_IRGRP
                | stat.S_IXGRP
                | stat.S_IROTH
                | stat.S_IXOTH,
                os.getuid(),
                os.getgid(),
                now_ns,
                now_ns,
                now_ns,
            ),
        )
        self.cursor.execute(
            "INSERT INTO contents (name, parent_inode, inode) VALUES (?,?,?)",
            (b'..', pyfuse3.ROOT_INODE, pyfuse3.ROOT_INODE),
        )

    def get_row(self, *a: Any, **kw: Any) -> sqlite3.Row:
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

    async def lookup(
        self, parent_inode: InodeT, name: bytes, ctx: RequestContext
    ) -> EntryAttributes:
        if name == b'.':
            inode = parent_inode
        elif name == b'..':
            inode = self.get_row("SELECT * FROM contents WHERE inode=?", (parent_inode,))[
                'parent_inode'
            ]
        else:
            try:
                inode = self.get_row(
                    "SELECT * FROM contents WHERE name=? AND parent_inode=?", (name, parent_inode)
                )['inode']
            except NoSuchRowError:
                raise (pyfuse3.FUSEError(errno.ENOENT))

        return await self.getattr(InodeT(inode), ctx)

    async def getattr(self, inode: InodeT, ctx: RequestContext | None = None) -> EntryAttributes:
        try:
            row = self.get_row("SELECT * FROM inodes WHERE id=?", (inode,))
        except NoSuchRowError:
            raise (pyfuse3.FUSEError(errno.ENOENT))

        entry = EntryAttributes()
        entry.st_ino = inode
        entry.generation = 0
        entry.entry_timeout = 300
        entry.attr_timeout = 300
        entry.st_mode = row['mode']
        entry.st_nlink = self.get_row("SELECT COUNT(inode) FROM contents WHERE inode=?", (inode,))[
            0
        ]
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

    async def readlink(self, inode: InodeT, ctx: RequestContext) -> bytes:
        return self.get_row('SELECT * FROM inodes WHERE id=?', (inode,))['target']

    async def opendir(self, inode: InodeT, ctx: RequestContext) -> FileHandleT:
        # For simplicity, we use the inode as file handle
        return FileHandleT(inode)

    async def readdir(self, fh: FileHandleT, start_id: int, token: ReaddirToken) -> None:
        if start_id == 0:
            off = -1
        else:
            off = start_id

        cursor2 = self.db.cursor()
        cursor2.execute(
            "SELECT * FROM contents WHERE parent_inode=? AND rowid > ? ORDER BY rowid", (fh, off)
        )

        for row in cursor2:
            pyfuse3.readdir_reply(
                token, row['name'], await self.getattr(InodeT(row['inode'])), row['rowid']
            )

    async def unlink(self, parent_inode: InodeT, name: bytes, ctx: RequestContext) -> None:
        entry = await self.lookup(parent_inode, name, ctx)

        if stat.S_ISDIR(entry.st_mode):
            raise pyfuse3.FUSEError(errno.EISDIR)

        self._remove(parent_inode, name, entry)

    async def rmdir(self, parent_inode: InodeT, name: bytes, ctx: RequestContext) -> None:
        entry = await self.lookup(parent_inode, name, ctx)

        if not stat.S_ISDIR(entry.st_mode):
            raise pyfuse3.FUSEError(errno.ENOTDIR)

        self._remove(parent_inode, name, entry)

    def _remove(self, parent_inode: InodeT, name: bytes, entry: EntryAttributes) -> None:
        if (
            self.get_row("SELECT COUNT(inode) FROM contents WHERE parent_inode=?", (entry.st_ino,))[
                0
            ]
            > 0
        ):
            raise pyfuse3.FUSEError(errno.ENOTEMPTY)

        self.cursor.execute(
            "DELETE FROM contents WHERE name=? AND parent_inode=?", (name, parent_inode)
        )

        if entry.st_nlink == 1 and entry.st_ino not in self.inode_open_count:
            self.cursor.execute("DELETE FROM inodes WHERE id=?", (entry.st_ino,))

    async def symlink(
        self, parent_inode: InodeT, name: bytes, target: bytes, ctx: RequestContext
    ) -> EntryAttributes:
        mode = (
            stat.S_IFLNK
            | stat.S_IRUSR
            | stat.S_IWUSR
            | stat.S_IXUSR
            | stat.S_IRGRP
            | stat.S_IWGRP
            | stat.S_IXGRP
            | stat.S_IROTH
            | stat.S_IWOTH
            | stat.S_IXOTH
        )
        return await self._create(parent_inode, name, mode, ctx, target=target)

    async def rename(
        self,
        parent_inode_old: InodeT,
        name_old: bytes,
        parent_inode_new: InodeT,
        name_new: bytes,
        flags: int,
        ctx: RequestContext,
    ) -> None:
        if flags != 0:
            raise FUSEError(errno.EINVAL)

        entry_old = await self.lookup(parent_inode_old, name_old, ctx)

        entry_new = None
        try:
            entry_new = await self.lookup(
                parent_inode_new,
                name_new if isinstance(name_new, bytes) else name_new.encode(),
                ctx,
            )
        except pyfuse3.FUSEError as exc:
            if exc.errno != errno.ENOENT:
                raise

        if entry_new is not None:
            self._replace(
                parent_inode_old, name_old, parent_inode_new, name_new, entry_old, entry_new
            )
        else:
            self.cursor.execute(
                "UPDATE contents SET name=?, parent_inode=? WHERE name=? AND parent_inode=?",
                (name_new, parent_inode_new, name_old, parent_inode_old),
            )

    def _replace(
        self,
        parent_inode_old: InodeT,
        name_old: bytes,
        parent_inode_new: InodeT,
        name_new: bytes,
        entry_old: EntryAttributes,
        entry_new: EntryAttributes,
    ) -> None:
        if (
            self.get_row(
                "SELECT COUNT(inode) FROM contents WHERE parent_inode=?", (entry_new.st_ino,)
            )[0]
            > 0
        ):
            raise pyfuse3.FUSEError(errno.ENOTEMPTY)

        self.cursor.execute(
            "UPDATE contents SET inode=? WHERE name=? AND parent_inode=?",
            (entry_old.st_ino, name_new, parent_inode_new),
        )
        self.db.execute(
            'DELETE FROM contents WHERE name=? AND parent_inode=?', (name_old, parent_inode_old)
        )

        if entry_new.st_nlink == 1 and entry_new.st_ino not in self.inode_open_count:
            self.cursor.execute("DELETE FROM inodes WHERE id=?", (entry_new.st_ino,))

    async def link(
        self, inode: InodeT, new_parent_inode: InodeT, new_name: bytes, ctx: RequestContext
    ) -> EntryAttributes:
        entry_p = await self.getattr(new_parent_inode, ctx)
        if entry_p.st_nlink == 0:
            log.warning(
                'Attempted to create entry %s with unlinked parent %d', new_name, new_parent_inode
            )
            raise FUSEError(errno.EINVAL)

        self.cursor.execute(
            "INSERT INTO contents (name, inode, parent_inode) VALUES(?,?,?)",
            (new_name, inode, new_parent_inode),
        )

        return await self.getattr(inode, ctx)

    async def setattr(
        self,
        inode: InodeT,
        attr: EntryAttributes,
        fields: SetattrFields,
        fh: FileHandleT | None,
        ctx: RequestContext,
    ) -> EntryAttributes:
        if fields.update_size:
            data = self.get_row('SELECT data FROM inodes WHERE id=?', (inode,))[0]
            if data is None:
                data = b''
            if len(data) < attr.st_size:
                data = data + b'\0' * (attr.st_size - len(data))
            else:
                data = data[: attr.st_size]
            self.cursor.execute(
                'UPDATE inodes SET data=?, size=? WHERE id=?',
                (memoryview(data), attr.st_size, inode),
            )
        if fields.update_mode:
            self.cursor.execute('UPDATE inodes SET mode=? WHERE id=?', (attr.st_mode, inode))

        if fields.update_uid:
            self.cursor.execute('UPDATE inodes SET uid=? WHERE id=?', (attr.st_uid, inode))

        if fields.update_gid:
            self.cursor.execute('UPDATE inodes SET gid=? WHERE id=?', (attr.st_gid, inode))

        if fields.update_atime:
            self.cursor.execute(
                'UPDATE inodes SET atime_ns=? WHERE id=?', (attr.st_atime_ns, inode)
            )

        if fields.update_mtime:
            self.cursor.execute(
                'UPDATE inodes SET mtime_ns=? WHERE id=?', (attr.st_mtime_ns, inode)
            )

        if fields.update_ctime:
            self.cursor.execute(
                'UPDATE inodes SET ctime_ns=? WHERE id=?', (attr.st_ctime_ns, inode)
            )
        else:
            self.cursor.execute(
                'UPDATE inodes SET ctime_ns=? WHERE id=?', (int(time() * 1e9), inode)
            )

        return await self.getattr(inode, ctx)

    async def mknod(
        self, parent_inode: InodeT, name: bytes, mode: int, rdev: int, ctx: RequestContext
    ) -> EntryAttributes:
        return await self._create(parent_inode, name, mode, ctx, rdev=rdev)

    async def mkdir(
        self, parent_inode: InodeT, name: bytes, mode: int, ctx: RequestContext
    ) -> EntryAttributes:
        return await self._create(parent_inode, name, mode, ctx)

    async def statfs(self, ctx: RequestContext) -> StatvfsData:
        stat_ = StatvfsData()

        stat_.f_bsize = 512
        stat_.f_frsize = 512

        size = self.get_row('SELECT SUM(size) FROM inodes')[0]
        stat_.f_blocks = size // stat_.f_frsize
        stat_.f_bfree = max(size // stat_.f_frsize, 1024)
        stat_.f_bavail = stat_.f_bfree

        inodes = self.get_row('SELECT COUNT(id) FROM inodes')[0]
        stat_.f_files = inodes
        stat_.f_ffree = max(inodes, 100)
        stat_.f_favail = stat_.f_ffree

        return stat_

    async def open(self, inode: InodeT, flags: int, ctx: RequestContext) -> FileInfo:
        self.inode_open_count[inode] += 1

        # For simplicity, we use the inode as file handle
        return FileInfo(fh=FileHandleT(inode))

    async def access(self, inode: InodeT, mode: int, ctx: RequestContext) -> bool:
        # Yeah, could be a function and has unused arguments
        # pylint: disable=R0201,W0613
        return True

    async def create(
        self, parent_inode: InodeT, name: bytes, mode: int, flags: int, ctx: RequestContext
    ) -> tuple[FileInfo, EntryAttributes]:
        # pylint: disable=W0612
        entry = await self._create(parent_inode, name, mode, ctx)
        self.inode_open_count[entry.st_ino] += 1
        # For simplicity, we use the inode as file handle
        return (FileInfo(fh=FileHandleT(entry.st_ino)), entry)

    async def _create(
        self,
        parent_inode: InodeT,
        name: bytes,
        mode: int,
        ctx: RequestContext,
        rdev: int = 0,
        target: bytes | None = None,
    ) -> EntryAttributes:
        if (await self.getattr(parent_inode, ctx)).st_nlink == 0:
            log.warning('Attempted to create entry %s with unlinked parent %d', name, parent_inode)
            raise FUSEError(errno.EINVAL)

        now_ns = int(time() * 1e9)
        self.cursor.execute(
            'INSERT INTO inodes (uid, gid, mode, mtime_ns, atime_ns, '
            'ctime_ns, target, rdev) VALUES(?, ?, ?, ?, ?, ?, ?, ?)',
            (ctx.uid, ctx.gid, mode, now_ns, now_ns, now_ns, target, rdev),
        )

        inode = cast(InodeT, self.cursor.lastrowid)
        self.db.execute(
            "INSERT INTO contents(name, inode, parent_inode) VALUES(?,?,?)",
            (name, inode, parent_inode),
        )
        return await self.getattr(inode, ctx)

    async def read(self, fh: FileHandleT, off: int, size: int) -> bytes:
        data = self.get_row('SELECT data FROM inodes WHERE id=?', (fh,))[0]
        if data is None:
            data = b''
        return data[off : off + size]

    async def write(self, fh: FileHandleT, off: int, buf: bytes) -> int:
        data = self.get_row('SELECT data FROM inodes WHERE id=?', (fh,))[0]
        if data is None:
            data = b''
        data = data[:off] + buf + data[off + len(buf) :]

        self.cursor.execute(
            'UPDATE inodes SET data=?, size=? WHERE id=?', (memoryview(data), len(data), fh)
        )
        return len(buf)

    async def release(self, fh: FileHandleT) -> None:
        inode = cast(InodeT, fh)
        self.inode_open_count[inode] -= 1

        if self.inode_open_count[inode] == 0:
            del self.inode_open_count[inode]
            if (await self.getattr(inode)).st_nlink == 0:
                self.cursor.execute("DELETE FROM inodes WHERE id=?", (inode,))


class NoUniqueValueError(Exception):
    def __str__(self) -> str:
        return 'Query generated more than 1 result row'


class NoSuchRowError(Exception):
    def __str__(self) -> str:
        return 'Query produced 0 result rows'


def init_logging(debug: bool = False) -> None:
    formatter = logging.Formatter(
        '%(asctime)s.%(msecs)03d %(threadName)s: [%(name)s] %(message)s',
        datefmt="%Y-%m-%d %H:%M:%S",
    )
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


def parse_args() -> Namespace:
    '''Parse command line'''

    parser = ArgumentParser()

    parser.add_argument('mountpoint', type=str, help='Where to mount the file system')
    parser.add_argument(
        '--debug', action='store_true', default=False, help='Enable debugging output'
    )
    parser.add_argument(
        '--debug-fuse', action='store_true', default=False, help='Enable FUSE debugging output'
    )

    return parser.parse_args()


if __name__ == '__main__':
    options = parse_args()
    init_logging(options.debug)
    operations = Operations()

    fuse_options = set(pyfuse3.default_options)
    fuse_options.add('fsname=tmpfs')
    fuse_options.discard('default_permissions')
    if options.debug_fuse:
        fuse_options.add('debug')
    pyfuse3.init(operations, options.mountpoint, fuse_options)

    try:
        trio.run(pyfuse3.main)
    except:
        pyfuse3.close(unmount=False)
        raise

    pyfuse3.close()
