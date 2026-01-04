#!/usr/bin/env python3
'''
passthroughfs.py - Example file system for pyfuse3

This file system mirrors the contents of a specified directory tree.

Caveats:

 * Inode generation numbers are not passed through but set to zero.

 * Block size (st_blksize) and number of allocated blocks (st_blocks) are not
   passed through.

 * Performance for large directories is not good, because the directory
   is always read completely.

 * There may be a way to break-out of the directory tree.

 * The readdir implementation is not fully POSIX compliant. If a directory
   contains hardlinks and is modified during a readdir call, readdir()
   may return some of the hardlinked files twice or omit them completely.

 * If you delete or rename files in the underlying file system, the
   passthrough file system will get confused.

Copyright ©  Nikolaus Rath <Nikolaus.org>

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
import faulthandler
import logging
import os
import stat as stat_m
import sys
from argparse import ArgumentParser, Namespace
from collections import defaultdict
from collections.abc import Sequence
from os import fsdecode, fsencode
from typing import cast

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

faulthandler.enable()

log = logging.getLogger(__name__)


class Operations(pyfuse3.Operations):
    def __init__(self, source: str, enable_writeback_cache: bool = False) -> None:
        super().__init__()
        self.enable_writeback_cache = enable_writeback_cache
        self._inode_path_map: dict[InodeT, str | set[str]] = {pyfuse3.ROOT_INODE: source}
        self._lookup_cnt: defaultdict[InodeT, int] = defaultdict(lambda: 0)
        self._fd_inode_map: dict[int, InodeT] = dict()
        self._inode_fd_map: dict[InodeT, int] = dict()
        self._fd_open_count: dict[int, int] = dict()

    def _inode_to_path(self, inode: InodeT) -> str:
        try:
            val = self._inode_path_map[inode]
        except KeyError:
            raise FUSEError(errno.ENOENT)

        if isinstance(val, set):
            # In case of hardlinks, pick any path
            val = next(iter(val))
        return val

    def _add_path(self, inode: InodeT, path: str) -> None:
        log.debug('_add_path for %d, %s', inode, path)
        self._lookup_cnt[inode] += 1

        # With hardlinks, one inode may map to multiple paths.
        if inode not in self._inode_path_map:
            self._inode_path_map[inode] = path
            return

        val = self._inode_path_map[inode]
        if isinstance(val, set):
            val.add(path)
        elif val != path:
            self._inode_path_map[inode] = {path, val}

    async def forget(self, inode_list: Sequence[tuple[InodeT, int]]) -> None:
        for inode, nlookup in inode_list:
            if self._lookup_cnt[inode] > nlookup:
                self._lookup_cnt[inode] -= nlookup
                continue
            log.debug('forgetting about inode %d', inode)
            assert inode not in self._inode_fd_map
            del self._lookup_cnt[inode]
            try:
                del self._inode_path_map[inode]
            except KeyError:  # may have been deleted
                pass

    async def lookup(
        self, parent_inode: InodeT, name: bytes, ctx: RequestContext
    ) -> EntryAttributes:
        name_str = fsdecode(name)
        log.debug('lookup for %s in %d', name_str, parent_inode)
        path = os.path.join(self._inode_to_path(parent_inode), name_str)
        attr = self._getattr(path=path)
        if name_str != '.' and name_str != '..':
            self._add_path(InodeT(attr.st_ino), path)
        return attr

    async def getattr(self, inode: InodeT, ctx: RequestContext | None = None) -> EntryAttributes:
        if inode in self._inode_fd_map:
            return self._getattr(fd=self._inode_fd_map[inode])
        else:
            return self._getattr(path=self._inode_to_path(inode))

    def _getattr(self, path: str | None = None, fd: int | None = None) -> EntryAttributes:
        assert fd is None or path is None
        assert not (fd is None and path is None)
        try:
            if fd is None:
                assert path is not None
                stat = os.lstat(path)
            else:
                stat = os.fstat(fd)
        except OSError as exc:
            assert exc.errno is not None
            raise FUSEError(exc.errno)

        entry = EntryAttributes()
        for attr in (
            'st_ino',
            'st_mode',
            'st_nlink',
            'st_uid',
            'st_gid',
            'st_rdev',
            'st_size',
            'st_atime_ns',
            'st_mtime_ns',
            'st_ctime_ns',
        ):
            setattr(entry, attr, getattr(stat, attr))
        entry.generation = 0
        entry.entry_timeout = 0
        entry.attr_timeout = 0
        entry.st_blksize = 512
        entry.st_blocks = (entry.st_size + entry.st_blksize - 1) // entry.st_blksize

        return entry

    async def readlink(self, inode: InodeT, ctx: RequestContext) -> bytes:
        path = self._inode_to_path(inode)
        try:
            target = os.readlink(path)
        except OSError as exc:
            assert exc.errno is not None
            raise FUSEError(exc.errno)
        return fsencode(target)

    async def opendir(self, inode: InodeT, ctx: RequestContext) -> FileHandleT:
        # For simplicity, we use the inode as file handle
        return FileHandleT(inode)

    async def readdir(self, fh: FileHandleT, start_id: int, token: ReaddirToken) -> None:
        path = self._inode_to_path(InodeT(fh))
        log.debug('reading %s', path)
        entries: list[tuple[InodeT, str, EntryAttributes]] = []
        for name in os.listdir(path):
            if name == '.' or name == '..':
                continue
            attr = self._getattr(path=os.path.join(path, name))
            entries.append((InodeT(attr.st_ino), name, attr))

        log.debug('read %d entries, starting at %d', len(entries), start_id)

        # This is not fully posix compatible. If there are hardlinks
        # (two names with the same inode), we don't have a unique
        # offset to start in between them. Note that we cannot simply
        # count entries, because then we would skip over entries
        # (or return them more than once) if the number of directory
        # entries changes between two calls to readdir().
        for ino, name, attr in sorted(entries):
            if ino <= start_id:
                continue
            if not pyfuse3.readdir_reply(token, fsencode(name), attr, ino):
                break
            self._add_path(attr.st_ino, os.path.join(path, name))

    async def unlink(self, parent_inode: InodeT, name: bytes, ctx: RequestContext) -> None:
        name_str = fsdecode(name)
        parent = self._inode_to_path(parent_inode)
        path = os.path.join(parent, name_str)
        try:
            inode = os.lstat(path).st_ino
            os.unlink(path)
        except OSError as exc:
            assert exc.errno is not None
            raise FUSEError(exc.errno)
        if inode in self._lookup_cnt:
            self._forget_path(InodeT(inode), path)

    async def rmdir(self, parent_inode: InodeT, name: bytes, ctx: RequestContext) -> None:
        name_str = fsdecode(name)
        parent = self._inode_to_path(parent_inode)
        path = os.path.join(parent, name_str)
        try:
            inode = os.lstat(path).st_ino
            os.rmdir(path)
        except OSError as exc:
            assert exc.errno is not None
            raise FUSEError(exc.errno)
        if inode in self._lookup_cnt:
            self._forget_path(InodeT(inode), path)

    def _forget_path(self, inode: InodeT, path: str) -> None:
        log.debug('forget %s for %d', path, inode)
        val = self._inode_path_map[inode]
        if isinstance(val, set):
            val.remove(path)
            if len(val) == 1:
                self._inode_path_map[inode] = next(iter(val))
        else:
            del self._inode_path_map[inode]

    async def symlink(
        self, parent_inode: InodeT, name: bytes, target: bytes, ctx: RequestContext
    ) -> EntryAttributes:
        name_str = fsdecode(name)
        target_str = fsdecode(target)
        parent = self._inode_to_path(parent_inode)
        path = os.path.join(parent, name_str)
        try:
            os.symlink(target_str, path)
            os.lchown(path, ctx.uid, ctx.gid)
        except OSError as exc:
            assert exc.errno is not None
            raise FUSEError(exc.errno)
        inode = InodeT(os.lstat(path).st_ino)
        self._add_path(inode, path)
        return await self.getattr(inode, ctx)

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

        name_old_str = fsdecode(name_old)
        name_new_str = fsdecode(name_new)
        parent_old = self._inode_to_path(parent_inode_old)
        parent_new = self._inode_to_path(parent_inode_new)
        path_old = os.path.join(parent_old, name_old_str)
        path_new = os.path.join(parent_new, name_new_str)
        try:
            os.rename(path_old, path_new)
            inode = cast(InodeT, os.lstat(path_new).st_ino)
        except OSError as exc:
            assert exc.errno is not None
            raise FUSEError(exc.errno)
        if inode not in self._lookup_cnt:
            return

        val = self._inode_path_map[inode]
        if isinstance(val, set):
            assert len(val) > 1
            val.add(path_new)
            val.remove(path_old)
        else:
            assert val == path_old
            self._inode_path_map[inode] = path_new

    async def link(
        self, inode: InodeT, new_parent_inode: InodeT, new_name: bytes, ctx: RequestContext
    ) -> EntryAttributes:
        new_name_str = fsdecode(new_name)
        parent = self._inode_to_path(new_parent_inode)
        path = os.path.join(parent, new_name_str)
        try:
            os.link(self._inode_to_path(inode), path, follow_symlinks=False)
        except OSError as exc:
            assert exc.errno is not None
            raise FUSEError(exc.errno)
        self._add_path(inode, path)
        return await self.getattr(inode, ctx)

    async def setattr(
        self,
        inode: InodeT,
        attr: EntryAttributes,
        fields: SetattrFields,
        fh: FileHandleT | None,
        ctx: RequestContext,
    ) -> EntryAttributes:
        try:
            if fields.update_size:
                if fh is None:
                    os.truncate(self._inode_to_path(inode), attr.st_size)
                else:
                    os.ftruncate(fh, attr.st_size)

            if fields.update_mode:
                # Under Linux, chmod always resolves symlinks so we should
                # actually never get a setattr() request for a symbolic
                # link.
                assert not stat_m.S_ISLNK(attr.st_mode)
                if fh is None:
                    os.chmod(self._inode_to_path(inode), stat_m.S_IMODE(attr.st_mode))
                else:
                    os.fchmod(fh, stat_m.S_IMODE(attr.st_mode))

            if fields.update_uid and fields.update_gid:
                if fh is None:
                    os.chown(
                        self._inode_to_path(inode), attr.st_uid, attr.st_gid, follow_symlinks=False
                    )
                else:
                    os.fchown(fh, attr.st_uid, attr.st_gid)

            elif fields.update_uid:
                if fh is None:
                    os.chown(self._inode_to_path(inode), attr.st_uid, -1, follow_symlinks=False)
                else:
                    os.fchown(fh, attr.st_uid, -1)

            elif fields.update_gid:
                if fh is None:
                    os.chown(self._inode_to_path(inode), -1, attr.st_gid, follow_symlinks=False)
                else:
                    os.fchown(fh, -1, attr.st_gid)

            if fields.update_atime and fields.update_mtime:
                if fh is None:
                    os.utime(
                        self._inode_to_path(inode),
                        None,
                        follow_symlinks=False,
                        ns=(attr.st_atime_ns, attr.st_mtime_ns),
                    )
                else:
                    os.utime(fh, None, ns=(attr.st_atime_ns, attr.st_mtime_ns))
            elif fields.update_atime or fields.update_mtime:
                # We can only set both values, so we first need to retrieve the
                # one that we shouldn't be changing.
                if fh is None:
                    path = self._inode_to_path(inode)
                    oldstat = os.stat(path, follow_symlinks=False)
                else:
                    oldstat = os.fstat(fh)
                if not fields.update_atime:
                    attr.st_atime_ns = oldstat.st_atime_ns
                else:
                    attr.st_mtime_ns = oldstat.st_mtime_ns
                if fh is None:
                    os.utime(
                        path,  # pyright: ignore[reportPossiblyUnboundVariable]
                        None,
                        follow_symlinks=False,
                        ns=(attr.st_atime_ns, attr.st_mtime_ns),
                    )
                else:
                    os.utime(fh, None, ns=(attr.st_atime_ns, attr.st_mtime_ns))

        except OSError as exc:
            assert exc.errno is not None
            raise FUSEError(exc.errno)

        return await self.getattr(inode, ctx)

    async def mknod(
        self, parent_inode: InodeT, name: bytes, mode: int, rdev: int, ctx: RequestContext
    ) -> EntryAttributes:
        path = os.path.join(self._inode_to_path(parent_inode), fsdecode(name))
        try:
            os.mknod(path, mode=(mode & ~ctx.umask), device=rdev)
            os.chown(path, ctx.uid, ctx.gid)
        except OSError as exc:
            assert exc.errno is not None
            raise FUSEError(exc.errno)
        attr = self._getattr(path=path)
        self._add_path(attr.st_ino, path)
        return attr

    async def mkdir(
        self, parent_inode: InodeT, name: bytes, mode: int, ctx: RequestContext
    ) -> EntryAttributes:
        path = os.path.join(self._inode_to_path(parent_inode), fsdecode(name))
        try:
            os.mkdir(path, mode=(mode & ~ctx.umask))
            os.chown(path, ctx.uid, ctx.gid)
        except OSError as exc:
            assert exc.errno is not None
            raise FUSEError(exc.errno)
        attr = self._getattr(path=path)
        self._add_path(attr.st_ino, path)
        return attr

    async def statfs(self, ctx: RequestContext) -> StatvfsData:
        root = self._inode_path_map[pyfuse3.ROOT_INODE]
        assert isinstance(root, str)
        stat_ = StatvfsData()
        try:
            statfs = os.statvfs(root)
        except OSError as exc:
            assert exc.errno is not None
            raise FUSEError(exc.errno)
        for attr in (
            'f_bsize',
            'f_frsize',
            'f_blocks',
            'f_bfree',
            'f_bavail',
            'f_files',
            'f_ffree',
            'f_favail',
        ):
            setattr(stat_, attr, getattr(statfs, attr))
        stat_.f_namemax = statfs.f_namemax - (len(root) + 1)
        return stat_

    async def open(self, inode: InodeT, flags: int, ctx: RequestContext) -> FileInfo:
        if inode in self._inode_fd_map:
            fd = self._inode_fd_map[inode]
            self._fd_open_count[fd] += 1
            return FileInfo(fh=FileHandleT(fd))
        assert flags & os.O_CREAT == 0
        try:
            fd = os.open(self._inode_to_path(inode), flags)
        except OSError as exc:
            assert exc.errno is not None
            raise FUSEError(exc.errno)
        self._inode_fd_map[inode] = fd
        self._fd_inode_map[fd] = inode
        self._fd_open_count[fd] = 1
        return FileInfo(fh=cast(FileHandleT, fd))

    async def create(
        self, parent_inode: InodeT, name: bytes, mode: int, flags: int, ctx: RequestContext
    ) -> tuple[FileInfo, EntryAttributes]:
        path = os.path.join(self._inode_to_path(parent_inode), fsdecode(name))
        try:
            fd = os.open(path, flags | os.O_CREAT | os.O_TRUNC)
        except OSError as exc:
            assert exc.errno is not None
            raise FUSEError(exc.errno)
        attr = self._getattr(fd=fd)
        self._add_path(attr.st_ino, path)
        self._inode_fd_map[attr.st_ino] = fd
        self._fd_inode_map[fd] = attr.st_ino
        self._fd_open_count[fd] = 1
        return (FileInfo(fh=cast(FileHandleT, fd)), attr)

    async def read(self, fh: FileHandleT, off: int, size: int) -> bytes:
        os.lseek(fh, off, os.SEEK_SET)
        return os.read(fh, size)

    async def write(self, fh: FileHandleT, off: int, buf: bytes) -> int:
        os.lseek(fh, off, os.SEEK_SET)
        return os.write(fh, buf)

    async def release(self, fh: FileHandleT) -> None:
        if self._fd_open_count[fh] > 1:
            self._fd_open_count[fh] -= 1
            return

        del self._fd_open_count[fh]
        inode = self._fd_inode_map[fh]
        del self._inode_fd_map[inode]
        del self._fd_inode_map[fh]
        try:
            os.close(fh)
        except OSError as exc:
            assert exc.errno is not None
            raise FUSEError(exc.errno)


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


def parse_args(args: list[str]) -> Namespace:
    '''Parse command line'''

    parser = ArgumentParser()

    parser.add_argument('source', type=str, help='Directory tree to mirror')
    parser.add_argument('mountpoint', type=str, help='Where to mount the file system')
    parser.add_argument(
        '--debug', action='store_true', default=False, help='Enable debugging output'
    )
    parser.add_argument(
        '--debug-fuse', action='store_true', default=False, help='Enable FUSE debugging output'
    )
    parser.add_argument(
        '--enable-writeback-cache',
        action='store_true',
        default=False,
        help='Enable writeback cache (default: disabled)',
    )

    return parser.parse_args(args)


def main() -> None:
    options = parse_args(sys.argv[1:])
    init_logging(options.debug)
    operations = Operations(options.source, enable_writeback_cache=options.enable_writeback_cache)

    log.debug('Mounting...')
    fuse_options = set(pyfuse3.default_options)
    fuse_options.add('fsname=passthroughfs')
    if options.debug_fuse:
        fuse_options.add('debug')
    pyfuse3.init(operations, options.mountpoint, fuse_options)

    try:
        log.debug('Entering main loop..')
        trio.run(pyfuse3.main)
    except:
        pyfuse3.close(unmount=False)
        raise

    log.debug('Unmounting..')
    pyfuse3.close()


if __name__ == '__main__':
    main()
