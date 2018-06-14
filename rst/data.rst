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

   The default options are:

   * ``default_permissions`` enables permission checking by kernel.
     Without this any umask (or uid/gid) would not have an effect.

   * ``splice_write`` just means to use splice if possible (i.e., if data is
     passed in a fd), and can be overriden using FUSE_BUF_NO_SPLICE. So it's a
     good idea to always activate it.

   * ``splice_read`` means that requests are spliced from the fuse fd to a
     (thread-specific) intermediate pipe (this is presumably done to prevent
     the write handler from reading part of the next request). If splice_read
     is not set, fuse instead reads the whole request into memory and passes
     this buffer along.  If we eventually read the request into a buffer anyway
     (as we have to if we want to create a Python object), using splice_read()
     is thus expected to *decrease* performance because of the intermediate
     pipe.

   * ``splice_move`` is a no-op as of Linux 2.6.21. However, it will become
     active as soon as some problems with the initial implementation have been
     solved.  If active, it's expected to improve performance because we move
     pages from the page instead of copying them.

   * ``nonempty`` allows mounts over non-empty file/dir.

   * ``big_writes`` enables larger than 4kB writes.

   .. versionadded:: 0.42

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
