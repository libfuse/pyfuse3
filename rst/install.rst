===================
 Installing LLFUSE
===================

.. highlight:: sh


Dependencies
============

In order to build and run LLFUSE you need the following software:

* Linux, FreeBSD or MacOS X system
* **Linux only**: Kernel 2.6.9 or newer. Starting with kernel
  2.6.26 you will get significantly better write performance, so under
  Linux you should actually use *2.6.26 or newer whenever possible*.
* **Linux only**: Version 2.8.0 or newer of the `FUSE
  <http://fuse.sourceforge.net/>`_ library.
* **FreeBSD only**: The `FUSE4BSD
  <http://www.freshports.org/sysutils/fusefs-kmod/>`_ kernel module.
* **OS-X only**: the `FUSE4X <http://fuse4x.org/>`_ package,
  version 0.9.1 or newer.
* `Python <http://www.python.org/>`_ 2.6 or newer (including Python
  3.x), installed with development headers
* `pkg-config <http://www.freedesktop.org/wiki/Software/pkg-config>`_ (only for building)
* A C compiler (only for building)


Stable releases
===============

LLFUSE can be installed like any other Python extension. Make sure
that you have the Python, FUSE and extended attribute ("xattr")
development headers installed, then download and extract the LLFUSE
tarball and run ::

  sudo python setup.py install

or :: 

  python setup.py install --user

Note that LLFUSE requires at least FUSE 2.8.0 and Python 2.6.

Development Version
===================

If you have checked out the unstable development version from the
Mercurial repository, a bit more effort is required. You need to also
have recent versions of Cython_ and Sphinx_ installed, and the
necessary commands are::

  python setup.py build_cython
  python setup.py build_ext --inplace
  python setup.py build_sphinx
  python setup.py install
  
  
.. _Cython: http://www.cython.org/
.. _Sphinx: http://sphinx.pocoo.org/
