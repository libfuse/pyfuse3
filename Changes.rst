===========
 Changelog
===========

.. currentmodule:: pyfuse3

Release 3.4.0 (2024-08-28)
==========================

* Cythonized with latest Cython 3.0.11 to support Python 3.13.

* CI: also test python 3.13, run mypy.

* Move ``_pyfuse3`` to ``pyfuse3._pyfuse3`` and add a compatibility wrapper
  for the old name.

* Move ``pyfuse3_asyncio`` to ``pyfuse3.asyncio`` and add a compatibility
  wrapper for the old name.

* Add `bytes` subclass `XAttrNameT` as the type of extended attribute names.

* Various fixes to type annotations.

* Add ``py.typed`` marker to enable external use of type annotations.


Release 3.3.0 (2023-08-06)
==========================

* Note: This is the first pyfuse3 release compatible with Cython 3.0.0 release.
  Cython 0.29.x is also still supported.

* Cythonized with latest Cython 3.0.0.

* Drop Python 3.6 and 3.7 support and testing, #71.

* CI: also test python 3.12. test on cython 0.29 and cython 3.0.

* Tell Cython that callbacks may raise exceptions, #80.

* Fix lookup in examples/hello.py, similar to #16.

* Misc. CI, testing, build and sphinx related fixes.





Release 3.2.3 (2023-05-09)
==========================

* cythonize with latest Cython 0.29.34 (brings Python 3.12 support)

* add a minimal pyproject.toml, require setuptools

* tests: fix integer overflow on 32-bit arches, fixes #47

* test: Use shutil.which() instead of external which(1) program

* setup.py: catch more generic OSError when searching Cython, fixes #63

* setup.py: require Cython >= 0.29

* fix basedir computation in setup.py (fix pip install -e .)

* use sphinx < 6.0 due to compatibility issues with more recent versions


Release 3.2.2 (2022-09-28)
==========================

* remove support for python 3.5 (broken, out of support by python devs)

* cythonize with latest Cython 0.29.x (brings Python 3.11 support)

* use github actions for CI, remove travis-ci

* update README: minimal maintenance, not developed

* update setup.py with tested python versions

* examples/tmpfs.py: work around strange kernel behaviour (calling SETATTR after
  UNLINK of a (not open) file): respond with ENOENT instead of crashing.


Release 3.2.1 (2021-09-17)
==========================

* Add type annotations

* Passing a XATTR_CREATE or XATTR_REPLACE to `setxattr` is now working
  correctly.

Release 3.2.0 (2020-12-30)
==========================

* Fix long-standing rounding error in file date handling when the nanosecond
  part of file dates were > 999999500.

* There is a new `pyfuse3.terminate()` function to gracefully end the
  main loop.


Release 3.1.1 (2020-10-06)
==========================

* No source changes. Regenerated Cython files with Cython 0.29.21 for Python 3.9
  compatibility.


Release 3.1.0 (2020-05-31)
==========================

* Made compatible with newest Trio module.


Release 3.0.0 (2020-05-08)
==========================

* Changed `~Operations.create` handler to return a `FileInfo` struct to allow
  for modification of certain kernel file attributes, e.g. ``direct_io``.

  Note that this change breaks backwards compatibility, code that depends
  on the old behavior needs to be changed.


Release 2.0.0
=============

* Changed `~Operations.open` handler to return the new `FileInfo` struct to
  allow for modification of certain kernel file attributes, e.g. ``direct_io``.

  Note that this change breaks backwards compatibility, code that depends on the old
  behavior needs to be changed.

Release 1.3.1 (2019-07-17)
==========================

* Fixed a bug in the :file:`hello_asyncio.py` example.

Release 1.3 (2019-06-02)
========================

* Fixed a bug in the :file:`tmpfs.py` and :file:`passthroughfs.py` example
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
