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

   .. attribute:: st_ino

   .. attribute:: generation

      The inode generation number.

   .. attribute:: entry_timeout

      Validity timeout (in seconds) for the name of the directory entry

   .. attribute:: attr_timeout

      Validity timeout (in seconds) for the attributes

   .. attribute:: st_mode

   .. attribute:: st_nlink

   .. attribute:: st_uid

   .. attribute:: st_gid

   .. attribute:: st_rdev

   .. attribute:: st_size

   .. attribute:: st_blksize

   .. attribute:: st_blocks

   .. attribute:: st_atime

      Time of access time in seconds. Floating point numbers may be used.

   .. attribute:: st_ctime

      Time of last status change in seconds. Floating point numbers may be used.

   .. attribute:: st_mtime

      Time of last modification in seconds. Floating point numbers may be used.

   .. attribute:: st_atime_ns

      Time of last access in nanoseconds. Only integer values
      may be used. If specified, takes precedence over `st_atime`.

   .. attribute:: st_ctime_ns

      Time of last status change in nanoseconds. Only integer values
      may be used. If specified, takes precedence over `st_ctime`.

   .. attribute:: st_mtime_ns

      Time of last modification in nanoseconds. Only integer values
      may be used. If specified, takes precedence over `st_mtime`.

