'''
aio.pxi

asyncio/Trio compatibility layer for pyfuse3

Copyright © 2018 JustAnotherArchivist, Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

import asyncio
import contextlib
import sys
try:
    import trio
except ImportError:
    trio = None


_aio_implementation = 'trio' # Possible values: 'asyncio' or 'trio'
_aio = None
_aio_read_lock = None


###########
# asyncio #
###########

class _AsyncioCompatibilityLayer:
    def __repr__(self):
        return '<pyfuse3 asyncio compatibility layer>'
_asyncio_layer = _AsyncioCompatibilityLayer()

class _AsyncioHazmatCompatibilityLayer:
    def __repr__(self):
        return '<pyfuse3 asyncio hazmat compatibility layer>'
_asyncio_layer.hazmat = _AsyncioHazmatCompatibilityLayer()

async def _wait_readable_asyncio(fd):
    future = asyncio.Future()
    loop = asyncio.get_event_loop()
    loop.add_reader(fd, future.set_result, None)
    future.add_done_callback(lambda f: loop.remove_reader(fd))
    await future
_asyncio_layer.hazmat.wait_readable = _wait_readable_asyncio

def _current_task_asyncio():
    if sys.version_info < (3, 7):
        return asyncio.Task.current_task()
    else:
        return asyncio.current_task()
_asyncio_layer.hazmat.current_task = _current_task_asyncio

class _AsyncioNursery:
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
            done, pending = await asyncio.wait(tuple(self.tasks)) # Create a copy of the task list to ensure that it's not a problem when self.tasks is modified
            for task in done:
                self.tasks.discard(task)
            # We waited for ALL_COMPLETED (default value of 'when' arg to asyncio.wait), so all tasks should be completed. If that's not the case, something's seriously wrong.
            assert len(pending) == 0
_asyncio_layer.open_nursery = _AsyncioNursery


########
# Trio #
########

# Nothing needed, we simply set _aio = trio below


##############
# Management #
##############

def _set_aio(aio_implementation):
    if aio_implementation not in ('asyncio', 'trio'):
        raise ValueError('Invalid aio')
    if aio_implementation == 'trio' and trio is None:
        raise RuntimeError('trio unavailable')
    global _aio_implementation, _aio, _aio_read_lock
    _aio_implementation = aio_implementation
    if aio_implementation == 'asyncio':
        _aio_read_lock = asyncio.Lock()
        _aio = _asyncio_layer
    else:
        _aio_read_lock = trio.Lock()
        _aio = trio
