'''
pyfuse3.pyi

Type annotation stubs for the external API in pyfuse3.pyx.

Copyright © 2021 Oliver Galvin

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

from _pyfuse3 import Operations, async_wrapper, FileHandleT, FileNameT, FlagT, InodeT, ModeT
from typing import List, Literal, Mapping

NamespaceT = Literal["system", "user"]
StatDict = Mapping[str, int]

default_options: frozenset[str]

class ReaddirToken:
    pass

class RequestContext:
    uid: int
    pid: int
    gid: int
    umask: int

    def __getstate__(self) -> None: ...

class SetattrFields:
    update_atime: bool
    update_mtime: bool
    update_ctime: bool
    update_mode: bool
    update_uid: bool
    update_gid: bool
    update_size: bool

    def __cinit__(self) -> None: ...
    def __getstate__(self) -> None: ...

class EntryAttributes:
    st_ino: InodeT
    generation: int
    entry_timeout: int
    attr_timeout: int
    st_mode: ModeT
    st_nlink: int
    st_uid: int
    st_gid: int
    st_rdev: int
    st_size: int
    st_blksize: int
    st_blocks: int
    st_atime_ns: int
    st_ctime_ns: int
    st_mtime_ns: int
    st_birthtime_ns: int

    def __cinit__(self) -> None: ...
    def __getstate__(self) -> StatDict: ...
    def __setstate__(self, state: StatDict) -> None: ...


class FileInfo:
    fh: FileHandleT
    direct_io: bool
    keep_cache: bool
    nonseekable: bool

    def __cinit__(self, fh: FileHandleT, direct_io: bool, keep_cache: bool, nonseekable: bool) -> None: ...
#    def _copy_to_fuse(self, fuse_file_info *out) -> None: ...

class StatvfsData:
    f_bsize: int
    f_frsize: int
    f_blocks: int
    f_bfree: int
    f_bavail: int
    f_files: int
    f_ffree: int
    f_favail: int
    f_namemax: int

    def __cinit__(self) -> None: ...
    def __getstate__(self) -> StatDict: ...
    def __setstate__(self, state: StatDict) -> None: ...

class FUSEError(Exception):
    errno: int

    def __cinit__(self, errno: int) -> None: ...
    def __str__(self) -> str: ...

def listdir(path: str) -> List[str]: ...
def syncfs(path: str) -> str: ...
def setxattr(path: str, name: str, value: bytes, namespace: NamespaceT) -> None: ...
def getxattr(path: str, name: str, size_guess: int, namespace: NamespaceT) -> bytes: ...
def init(ops: Operations, mountpoint: str, options: set[str]) -> None: ...
def main(min_tasks: int, max_tasks: int) -> None: ...
def terminate() -> None: ...
def close(unmount: bool) -> None: ...
def invalidate_inode(inode: InodeT, attr_only: bool) -> None: ...
def invalidate_entry(inode_p: InodeT, name: bytes, deleted: InodeT) -> None: ...
def invalidate_entry_async(inode_p: InodeT, name: bytes, deleted: InodeT, ignore_enoent: bool) -> None: ...
def notify_store(inode: InodeT, offset: int, data: bytes) -> None: ...
def get_sup_groups(pid: int) -> set[int]: ...
def readdir_reply(token: ReaddirToken, name: bytes, attr: EntryAttributes, next_id: int) -> bool: ...
