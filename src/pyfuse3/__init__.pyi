'''
__init__.pyi

Type annotation stubs for the external API in __init__.pyx.

Copyright © 2021 Oliver Galvin

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

# re-exports
from ._pyfuse3 import (
    Operations as Operations,
    FileHandleT as FileHandleT,
    FileNameT as FileNameT,
    FlagT as FlagT,
    InodeT as InodeT,
    ModeT as ModeT,
    XAttrNameT as XAttrNameT
)
from trio.lowlevel import TrioToken
from typing import List, Literal, Mapping, Optional, Union

ENOATTR: int
RENAME_EXCHANGE: FlagT
RENAME_NOREPLACE: FlagT
ROOT_INODE: InodeT
trio_token: Optional[TrioToken]
__version__: str

NamespaceT = Literal["system", "user"]
StatDict = Mapping[str, int]

default_options: frozenset[str]

class ReaddirToken:
    pass

class RequestContext:
    @property
    def uid(self) -> int: ...
    @property
    def pid(self) -> int: ...
    @property
    def gid(self) -> int: ...
    @property
    def umask(self) -> int: ...

    def __getstate__(self) -> None: ...

class SetattrFields:
    @property
    def update_atime(self) -> bool: ...
    @property
    def update_mtime(self) -> bool: ...
    @property
    def update_ctime(self) -> bool: ...
    @property
    def update_mode(self) -> bool: ...
    @property
    def update_uid(self) -> bool: ...
    @property
    def update_gid(self) -> bool: ...
    @property
    def update_size(self) -> bool: ...

    def __init__(self) -> None: ...
    def __getstate__(self) -> None: ...

class EntryAttributes:
    st_ino: InodeT
    generation: int
    entry_timeout: Union[float, int]
    attr_timeout: Union[float, int]
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

    def __init__(self) -> None: ...
    def __getstate__(self) -> StatDict: ...
    def __setstate__(self, state: StatDict) -> None: ...


class FileInfo:
    fh: FileHandleT
    direct_io: bool
    keep_cache: bool
    nonseekable: bool

    def __init__(self, fh: FileHandleT = ..., direct_io: bool = ..., keep_cache: bool = ..., nonseekable: bool = ...) -> None: ...

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

    def __init__(self) -> None: ...
    def __getstate__(self) -> StatDict: ...
    def __setstate__(self, state: StatDict) -> None: ...

class FUSEError(Exception):
    @property
    def errno(self) -> int: ...
    @property
    def errno_(self) -> int: ...

    def __init__(self, errno: int) -> None: ...
    def __str__(self) -> str: ...

def listdir(path: str) -> List[str]: ...
def syncfs(path: str) -> str: ...
def setxattr(path: str, name: str, value: bytes, namespace: NamespaceT = ...) -> None: ...
def getxattr(path: str, name: str, size_guess: int = ..., namespace: NamespaceT = ...) -> bytes: ...
def init(ops: Operations, mountpoint: str, options: set[str] = ...) -> None: ...
async def main(min_tasks: int = ..., max_tasks: int = ...) -> None: ...
def terminate() -> None: ...
def close(unmount: bool = ...) -> None: ...
def invalidate_inode(inode: InodeT, attr_only: bool = ...) -> None: ...
def invalidate_entry(inode_p: InodeT, name: FileNameT, deleted: InodeT = ...) -> None: ...
def invalidate_entry_async(inode_p: InodeT, name: FileNameT, deleted: InodeT = ..., ignore_enoent: bool = ...) -> None: ...
def notify_store(inode: InodeT, offset: int, data: bytes) -> None: ...
def get_sup_groups(pid: int) -> set[int]: ...
def readdir_reply(token: ReaddirToken, name: FileNameT, attr: EntryAttributes, next_id: int) -> bool: ...
