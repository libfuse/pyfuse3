=================
 Data Structures
=================

.. currentmodule:: llfuse

.. py:data:: ENOATTR

   This errorcode is unfortunately missing in the `errno` module,
   so it is provided by Python-LLFUSE instead.

.. py:data:: ROOT_INODE

   The inode of the root directory, i.e. the mount point of the file
   system.

.. py:data:: default_options

   This is a recommended set of options that should be passed to
   `llfuse.init` to get reasonable behavior and
   performance. Python-LLFUSE is compatible with any other combination
   of options as well, but you should only deviate from the defaults
   with good reason.

   (The :samp:`fsname=<foo>` option is guaranteed never to be included in the
   default options, so you can always safely add it to the set).

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
