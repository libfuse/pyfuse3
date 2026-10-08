==================
 Platform Support
==================

.. currentmodule:: pyfuse3

pyfuse3 supports Linux (its primary platform) and macOS. FreeBSD and NetBSD are only partially
supported and not regularly tested.


macOS
=====

On macOS, pyfuse3 uses the *libfuse3* library and kernel extension provided by macFUSE_. The
following differences to FUSE on Linux are relevant for file systems written with pyfuse3:

* macFUSE does not support *readdirplus* requests, so the kernel does not perform lookups for the
  entries returned by `~Operations.readdir`. pyfuse3 compensates for this by calling
  `~Operations.forget` for the reported entries right after the `~Operations.readdir` call has
  returned, so that the file system can implement `~Operations.readdir` in the same way on all
  platforms.

* macFUSE keeps directory entries in the kernel's vnode name cache until they are explicitly
  invalidated; there is no per-entry expiry, so the `~EntryAttributes.entry_timeout` is not
  observed. `invalidate_inode` (i.e., invalidation of cached attributes and data) works as on
  Linux.

* `invalidate_entry` and `invalidate_entry_async` work with macFUSE 5.3.1 and newer (whose kernel
  extension removes the item from the name cache when handling ``FUSE_NOTIFY_INVAL_ENTRY``). Earlier
  releases accept the notification (it succeeds) but their vnode name cache ignores it, so the entry
  is not looked up again.

* `notify_store` is not supported by macFUSE and raises `OSError` with errno ``ENOSYS``.

* macFUSE does not send poll requests, so `~Operations.poll` is never called.

* macFUSE does not offer the writeback cache, the POSIX ACL support and the support for lookups of
  :file:`.` and :file:`..` (see the ``enable_writeback_cache``, ``enable_acl`` and
  ``supports_dot_lookup`` attributes of `Operations`), so these settings have no effect.

* pyfuse3 uses the vanilla libfuse API of macFUSE (rather than its extended, Darwin specific API),
  so macOS specific attributes like the backup time or file flags cannot be set or reported, and
  extended attribute requests for the resource fork (``com.apple.ResourceFork``) are rejected by
  libfuse with ``ENOTSUP``.

* `default_options` additionally contains the ``noappledouble`` mount option, which prevents
  macOS from creating AppleDouble (``._*``) files on the file system. The macFUSE specific mount
  options are described in the `macFUSE wiki`_.

* macOS creates a ``com.apple.provenance`` extended attribute for every newly created file. File
  systems that do not support extended attributes should raise ``FUSEError(errno.ENOSYS)`` in
  `~Operations.setxattr` (the default), the error is then handled by macOS.

* The values of `RENAME_EXCHANGE` and `RENAME_NOREPLACE` correspond to the ``RENAME_SWAP`` and
  ``RENAME_EXCL`` flags of macOS' ``renameatx_np(2)``.

* `syncfs` calls ``sync(2)`` (which syncs all file systems and may return before the data has been
  written), because macOS has no ``syncfs(2)``.

* `get_sup_groups` retrieves the group ids from the kernel with ``sysctl(3)``. Note that the
  kernel stores at most 16 group ids per process.

* Unmounting a file system (with :manpage:`umount(8)` or `close`) works as on Linux. There is no
  ``fusermount`` command on macOS.

* Internally, the FUSE session file descriptor is not waited on directly (the macFUSE device does
  not support :manpage:`kqueue(2)`). Instead, a helper thread waits for the device to become
  readable with :manpage:`select(2)` and wakes up the event loop through a pipe.


.. _macFUSE: https://macfuse.github.io/
.. _`macFUSE wiki`: https://github.com/macfuse/macfuse/wiki/Mount-Options
