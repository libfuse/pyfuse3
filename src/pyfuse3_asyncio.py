'''
pyfuse3_asyncio.py

asyncio compatibility layer for pyfuse3

Copyright © 2018 Nikolaus Rath <Nikolaus.org>
Copyright © 2018 JustAnotherArchivist

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

import asyncio
import pyfuse3
import sys

Lock = asyncio.Lock


def enable():
    '''Switch pyfuse3 to asyncio mode.'''

    fake_trio = sys.modules['pyfuse3_asyncio']
    fake_trio.lowlevel = fake_trio
    pyfuse3.trio = fake_trio


def disable():
    '''Switch pyfuse3 to default (trio) mode.'''

    pyfuse3.trio = sys.modules['trio']


async def wait_readable(fd):
    future = asyncio.Future()
    loop = asyncio.get_event_loop()
    loop.add_reader(fd, future.set_result, None)
    future.add_done_callback(lambda f: loop.remove_reader(fd))
    await future


def current_task():
    if sys.version_info < (3, 7):
        return asyncio.Task.current_task()
    else:
        return asyncio.current_task()


class _Nursery:
    async def __aenter__(self):
        self.tasks = set()
        return self

    def start_soon(self, func, *args, name = None):
        if sys.version_info < (3, 7):
            task = asyncio.ensure_future(func(*args))
        else:
            task = asyncio.create_task(func(*args))
        task.name = name
        self.tasks.add(task)

    async def __aexit__(self, exc_type, exc_value, traceback):
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


def open_nursery():
    return _Nursery()
