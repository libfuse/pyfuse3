=================
 Data Structures
=================

.. currentmodule:: pyfuse3

.. py:data:: ENOATTR

   This errorcode is unfortunately missing in the `errno` module,
   so it is provided by pyfuse3 instead.

.. py:data:: ROOT_INODE

   The inode of the root directory, i.e. the mount point of the file
   system.

.. py:data:: RENAME_EXCHANGE

   A flag that may be passed to the `~Operations.rename` handler. When
   passed, the handler must atomically exchange the two paths (which
   must both exist).

.. py:data:: RENAME_NOREPLACE

   A flag that may be passed to the `~Operations.rename` handler. When
   passed, the handler must not replace an existing target.

.. py:data:: default_options

   This is a recommended set of options that should be passed to
   `pyfuse3.init` to get reasonable behavior and
   performance. pyfuse3 is compatible with any other combination
   of options as well, but you should only deviate from the defaults
   with good reason.

   (The :samp:`fsname=<foo>` option is guaranteed never to be included in the
   default options, so you can always safely add it to the set).

   The default options are:

   * ``default_permissions`` enables permission checking by kernel.
     Without this any umask (or uid/gid) would not have an effect.

.. autoexception:: FUSEError

.. autoclass:: RequestContext

   .. attribute:: pid

   .. attribute:: uid

   .. attribute:: gid

   .. attribute:: umask

.. autoclass:: StatvfsData

   .. attribute:: f_bsize

   .. attribute:: f_frsize

   .. attribute:: f_blocks

   .. attribute:: f_bfree

   .. attribute:: f_bavail

   .. attribute:: f_files

   .. attribute:: f_ffree

   .. attribute:: f_favail

   .. attribute:: f_namemax

.. autoclass:: EntryAttributes

   .. autoattribute:: st_ino

   .. autoattribute:: generation

   .. autoattribute:: entry_timeout

   .. autoattribute:: attr_timeout

   .. autoattribute:: st_mode

   .. autoattribute:: st_nlink

   .. autoattribute:: st_uid

   .. autoattribute:: st_gid

   .. autoattribute:: st_rdev

   .. autoattribute:: st_size

   .. autoattribute:: st_blksize

   .. autoattribute:: st_blocks

   .. autoattribute:: st_atime_ns

   .. autoattribute:: st_ctime_ns

   .. autoattribute:: st_mtime_ns

.. autoclass:: FileInfo

   .. autoattribute:: fh

      This attribute must be set to the file handle to be returned from
      `Operations.open`.

   .. autoattribute:: direct_io

      If true, signals to the kernel that this file should not be cached
      or buffered.

   .. autoattribute:: keep_cache

      If true, signals to the kernel that previously cached data for this
      inode is still valid, and should not be invalidated.

   .. autoattribute:: nonseekable

      If true, indicates that the file does not support seeking.

.. autoclass:: SetattrFields

   .. attribute:: update_atime

      If this attribute is true, it signals the `Operations.setattr`
      method that the `~EntryAttributes.st_atime_ns` field contains an
      updated value.

   .. attribute:: update_mtime

      If this attribute is true, it signals the `Operations.setattr`
      method that the `~EntryAttributes.st_mtime_ns` field contains an
      updated value.

   .. attribute:: update_mode

      If this attribute is true, it signals the `Operations.setattr`
      method that the `~EntryAttributes.st_mode` field contains an
      updated value.

   .. attribute:: update_uid

      If this attribute is true, it signals the `Operations.setattr`
      method that the `~EntryAttributes.st_uid` field contains an
      updated value.

   .. attribute:: update_gid

      If this attribute is true, it signals the `Operations.setattr`
      method that the `~EntryAttributes.st_gid` field contains an
      updated value.

   .. attribute:: update_size

      If this attribute is true, it signals the `Operations.setattr`
      method that the `~EntryAttributes.st_size` field contains an
      updated value.
