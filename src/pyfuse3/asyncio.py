'''
asyncio.py

asyncio compatibility layer for pyfuse3

Copyright © 2018 Nikolaus Rath <Nikolaus.org>
Copyright © 2018 JustAnotherArchivist

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

import asyncio
import collections
import sys
from typing import Any, Callable, Iterable, Optional, Set, Type

import pyfuse3
from ._pyfuse3 import FileHandleT

Lock = asyncio.Lock


def enable() -> None:
    '''Switch pyfuse3 to asyncio mode.'''

    fake_trio = sys.modules['pyfuse3.asyncio']
    fake_trio.lowlevel = fake_trio  # type: ignore
    fake_trio.from_thread = fake_trio  # type: ignore
    pyfuse3.trio = fake_trio  # type: ignore


def disable() -> None:
    '''Switch pyfuse3 to default (trio) mode.'''

    pyfuse3.trio = sys.modules['trio']  # type: ignore


def current_trio_token() -> str:
    return 'asyncio'


_read_futures = collections.defaultdict(set)


async def wait_readable(fd: FileHandleT) -> None:
    future: 'asyncio.Future[Any]' = asyncio.Future()
    _read_futures[fd].add(future)
    try:
        loop = asyncio.get_event_loop()
        loop.add_reader(fd, future.set_result, None)
        future.add_done_callback(lambda f: loop.remove_reader(fd))
        await future
    finally:
        _read_futures[fd].remove(future)
        if not _read_futures[fd]:
            del _read_futures[fd]


def notify_closing(fd: FileHandleT) -> None:
    for f in _read_futures[fd]:
        f.set_exception(ClosedResourceError())


class ClosedResourceError(Exception):
    pass


def current_task() -> 'Optional[asyncio.Task[Any]]':
    if sys.version_info < (3, 7):
        return asyncio.Task.current_task()
    else:
        return asyncio.current_task()


class _Nursery:
    async def __aenter__(self) -> "_Nursery":
        self.tasks: 'Set[asyncio.Task[Any]]' = set()
        return self

    def start_soon(
        self,
        func: Callable[..., Any],
        *args: Iterable[Any],
        name: Optional[str] = None
    ) -> None:
        if sys.version_info < (3, 7):
            task = asyncio.ensure_future(func(*args))
        else:
            task = asyncio.create_task(func(*args))
        task.name = name  # type: ignore
        self.tasks.add(task)

    async def __aexit__(
        self,
        exc_type: Optional[Type[BaseException]],
        exc_value: Optional[BaseException],
        traceback: Optional[Any]
    ) -> None:
        # Wait for tasks to finish
        while len(self.tasks):
            # Create a copy of the task list to ensure that it's not a problem
            # when self.tasks is modified
            done, pending = await asyncio.wait(tuple(self.tasks))
            for task in done:
                self.tasks.discard(task)

            # We waited for ALL_COMPLETED (default value of 'when' arg to
            # asyncio.wait), so all tasks should be completed. If that's not the
            # case, something's seriously wrong.
            assert len(pending) == 0


def open_nursery() -> _Nursery:
    return _Nursery()
