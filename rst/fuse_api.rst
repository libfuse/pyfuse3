====================
 FUSE API Functions
====================

.. currentmodule:: pyfuse3

.. autofunction:: init
.. autofunction:: main
.. autofunction:: terminate
.. autofunction:: close
.. autofunction:: invalidate_inode
.. autofunction:: invalidate_entry
.. autofunction:: invalidate_entry_async
.. autofunction:: notify_store
.. autofunction:: readdir_reply

.. py:data:: trio_token

   Set to the value returned by `trio.lowlevel.current_trio_token` while `main` is
   running. Can be used by other threads to run code in the main loop through
   `trio.from_thread.run`.
