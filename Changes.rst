===========
 Changelog
===========

.. currentmodule:: pyfuse3

Release 1.3 (2019-06-02)
========================

* Fixed a bug in the `tmpfs.py` and `passthroughfs.py` example
  file systems (so rename operations no longer fail).

Release 1.2 (2018-12-22)
========================

* Clarified that `invalidate_inode` may block in some circumstances.
* Added support for using the asyncio module instead of Trio.

Release 1.1 (2018-11-02)
========================

* Fixed :file:`examples/passthroughfs.py` - was not handling readdir()
  correctly.
* `invalidate_entry_async` now accepts an additional *ignore_enoent*
  parameter. When this is set, no errors are logged if the kernel is
  not actually aware of the entry that should have been removed.


Release 1.0 (2018-10-08)
========================

* Added a new `syncfs` function.


Release 0.9 (2018-09-27)
========================

* First release
* pyfuse3 was forked from python-llfuse - thanks for all the work!
* If you need compatibility with Python 2.x or libfuse 2.x, you may
  want to take a look at python-llfuse instead.
