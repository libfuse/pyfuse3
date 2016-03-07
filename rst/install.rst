==============
 Installation
==============

.. highlight:: sh


Dependencies
============

In order to build and run Python-LLFUSE you need the following software:

* Linux, FreeBSD, NetBSD or MacOS X system
* Python_ 2.6 or newer (including Python 3.x), installed with
  development headers
* The `setuptools`_ Python module, version 1.0 or newer.
* When running under Python 2.x, the `contextlib2`_ Python module from
  PyPi.
* the `pkg-config`_ tool
* the `attr`_ library
* A C compiler (only for building)

To run the unit tests, you will need

* The `py.test`_ module.

When using Linux, you also need:

* Kernel 2.6.9 or newer. Starting with kernel
  2.6.26 you will get significantly better write performance, so under
  Linux you should actually use *2.6.26 or newer whenever possible*.
* Version 2.9.0 or newer of the FUSE_ library, including development
  headers (typically distributions provide them in a *libfuse-devel*
  or *libfuse-dev* package).

In case of FreeBSD and NetBSD you will need:

* The FUSE4BSD_ kernel module.

For OS-X, you need:

* the OSXFUSE_ package.


Stable releases
===============

To install a stable Python-LLFUSE release:

1. Download and unpack the release tarball from https://pypi.python.org/pypi/llfuse/
2. Run ``python setup.py build_ext --inplace`` to build the C extension
3. Run ``python -m pytest test/`` to run a self-test. If this fails, ask
   for help on the `FUSE mailing list`_  or report a bug in the
   `issue tracker <https://bitbucket.org/nikratio/python-llfuse/issues>`_.
4. To install system-wide for all users, run ``sudo python setup.py
   install``. To install into :file:`~/.local`, run ``python
   setup.py install --user``.


Development Version
===================

If you have checked out the unstable development version from the
Mercurial repository, a bit more effort is required. You need to also
have Cython_ (0.24 or newer) and Sphinx_ (1.1 or newer) installed, and
the necessary commands are::

  python setup.py build_cython
  python setup.py build_ext --inplace
  python -m pytest test/
  python setup.py build_sphinx
  python setup.py install


.. _Cython: http://www.cython.org/
.. _Sphinx: http://sphinx.pocoo.org/
.. _Python: http://www.python.org/
.. _FUSE mailing list: https://lists.sourceforge.net/lists/listinfo/fuse-devel
.. _`py.test`: https://pypi.python.org/pypi/pytest/
.. _FUSE: http://github.com/libfuse/libfuse
.. _attr: http://savannah.nongnu.org/projects/attr/
.. _`pkg-config`: http://www.freedesktop.org/wiki/Software/pkg-config
.. _FUSE4BSD: http://www.freshports.org/sysutils/fusefs-kmod/
.. _OSXFUSE: http://osxfuse.github.io/
.. _setuptools: https://pypi.python.org/pypi/setuptools
.. _contextlib2: https://pypi.python.org/pypi/contextlib2/
