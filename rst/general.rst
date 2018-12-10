=====================
 General Information
=====================

.. currentmodule:: pyfuse3

.. _getting_started:

Getting started
===============

A file system is implemented by subclassing the `pyfuse3.Operations`
class and implementing the various request handlers. The handlers
respond to requests received from the FUSE kernel module and perform
functions like looking up the inode given a file name, looking up
attributes of an inode, opening a (file) inode for reading or writing
or listing the contents of a (directory) inode.

By default, pyfuse3 uses asynchronous I/O using Trio_, and most of the
documentation assumes that you are using Trio. If you'd rather use
asyncio, take a look at :ref:`asyncio Support <asyncio>`. If you would
like to use Trio (which is recommended) but you have not yet used Trio
before, please read the `Trio tutorial`_ first.

An instance of the operations class is passed to `pyfuse3.init` to
mount the file system. To enter the request handling loop, run
`pyfuse3.main` in a trio event loop. This function will return when
the file system should be unmounted again, which is done by calling
`pyfuse3.close`.

All character data (directory entry names, extended attribute names
and values, symbolic link targets etc) are passed as `bytes` and must
be returned as `bytes`.

For easier debugging, it is strongly recommended that applications
using pyfuse3 also make use of the faulthandler_ module.

.. _faulthandler: http://docs.python.org/3/library/faulthandler.html
.. _Trio tutorial: https://trio.readthedocs.io/en/latest/tutorial.html
.. _Trio: https://github.com/python-trio/trio

Lookup Counts
=============

Most file systems need to keep track which inodes are currently known
to the kernel. This is, for example, necessary to correctly implement
the *unlink* system call: when unlinking a directory entry whose
associated inode is currently opened, the file system must defer
removal of the inode (and thus the file contents) until it is no
longer in use by any process.

FUSE file systems achieve this by using "lookup counts". A lookup
count is a number that's associated with an inode. An inode with a
lookup count of zero is currently not known to the kernel. This means
that if there are no directory entries referring to such an inode it
can be safely removed, or (if a file system implements dynamic inode
numbers), the inode number can be safely recycled.

The lookup count of an inode is increased by every operation that
could make the inode "known" to the kernel. This includes e.g.
`~Operations.lookup`, `~Operations.create` and `~Operations.readdir`
(to determine if a given request handler affects the lookup count,
please refer to its description in the `Operations` class).  The
lookup count is decreased by calls to the `~Operations.forget`
handler.


FUSE and VFS Locking
====================

FUSE and the kernel's VFS layer provide some basic locking that FUSE
file systems automatically take advantage of. Specifically:

* Calls to `~Operations.rename`, `~Operations.create`,
  `~Operations.symlink`, `~Operations.mknod`, `~Operations.link` and
  `~Operations.mkdir` acquire a write-lock on the inode of the
  directory in which the respective operation takes place (two in case
  of rename).

* Calls to `~Operations.lookup` acquire a read-lock on the inode of the
  parent directory (meaning that lookups in the same directory may run
  concurrently, but never at the same time as e.g. a rename or mkdir
  operation).

* Unless writeback caching is enabled, calls to `~Operations.write`
  for the same inode are automatically serialized (i.e., there are
  never concurrent calls for the same inode even when multithreading
  is enabled).
