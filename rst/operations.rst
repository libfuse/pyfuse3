Request Handlers
================


.. currentmodule:: llfuse

.. autoclass:: Operations
  :members:

.. autoexception:: FUSEError

.. autoclass:: RequestContext

   .. attribute:: pid
   
   .. attribute:: uid
   
   .. attribute:: gid
   
   .. attribute:: umask
   

.. autoclass:: EntryAttributes

   .. attribute:: ino
   
   .. attribute:: generation

      The inode generation number.
      
   .. attribute:: entry_timeout

      Validity timeout (in seconds) for the name
      
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

   .. attribute:: st_ctime

   .. attribute:: st_mtime
