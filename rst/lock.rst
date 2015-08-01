=================
 The global lock
=================

.. currentmodule:: llfuse

Python-LLFUSE uses a global lock to synchronize concurrent requests. Since
the GIL already enforces that Python threads do not run concurrently,
this does not result in any additional performance penalties. However,
the use of an explicit lock allows direct control over which Python
thread is running at a given time.

Request handlers will always be called with the global lock acquired.
However, they may release the global lock for potentially time
consuming operations (like network or disk I/O), or to give other
threads a chance to run during longer computations.

Non-request handling threads may acquire the global lock to ensure
that the execution of a particular code block will not be interrupted
by any request handlers.

Obviously, any method that directly or indirectly releases the global
lock must be prepared to be called again while it has released the
lock. In addition, it (and all its callers) must not hold any prior
locks, since this may lead to deadlocks when re-acquiring the global
lock. For this reason it is crucial that every method that directly or
indirectly releases the lock is explicitly marked as such.


The global lock is controlled with the `lock` and `lock_released`
attributes of the `llfuse` module:

.. py:attribute:: lock_released

   Controls the global lock. This object can be used as a context
   manager for the ``with`` statement to execute a block of code
   with the global lock released.

.. py:attribute:: lock

   Controls the global lock. This object can be used as a context
   manager for the ``with`` statement to execute a block of code
   with the global lock acquired.

   Note that this object resembles a ``threading.Lock`` instance but
   is an instance of the `llfuse.Lock` class which is quite different from
   ``threading.Lock``.

The `lock` object has the following methods:

.. class:: llfuse.Lock

  .. automethod:: Lock.acquire()

  .. automethod:: Lock.release

  .. automethod:: Lock.yield_

