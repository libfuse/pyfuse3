===================
 Installing LLFUSE
===================

.. highlight:: sh


Dependencies
============

In order to build and run LLFUSE you need the following software:

* Linux, FreeBSD or MacOS X system
* Python_ 2.6 or newer (including Python 3.x), installed with
  development headers
* the `pkg-config`_ tool
* the `attr`_ library
* A C compiler (only for building)

When using Linux, you also need:

* Kernel 2.6.9 or newer. Starting with kernel
  2.6.26 you will get significantly better write performance, so under
  Linux you should actually use *2.6.26 or newer whenever possible*.
* Version 2.8.0 or newer of the FUSE_ library.

In case of FreeBSD, you will need:

* The FUSE4BSD_ kernel module.

For OS-X, you need:

* the FUSE4X_ package, version 0.9.1 or newer.


Stable releases
===============

LLFUSE can be installed like any other Python extension. Make sure
that you have all necessary dependencies installed (when installing
packages from a distribution, make sure to also install the
corresponding *-dev* or *-devel* development packages), then download
and extract the LLFUSE tarball and run ::

  sudo python setup.py install

or :: 

  python setup.py install --user


Development Version
===================

If you have checked out the unstable development version from the
Mercurial repository, a bit more effort is required. You need to also
have Cython_ (0.16 or newer) and Sphinx_ (1.1 or newer) installed, and
the necessary commands are::

  python setup.py build_cython
  python setup.py build_ext --inplace
  python setup.py build_sphinx
  python setup.py install
  
  
.. _Cython: http://www.cython.org/
.. _Sphinx: http://sphinx.pocoo.org/
.. _Python: http://www.python.org/
.. _FUSE: http://fuse.sourceforge.net/
.. _attr: http://savannah.nongnu.org/projects/attr/
.. _`pkg-config`: http://www.freedesktop.org/wiki/Software/pkg-config
.. _FUSE4BSD: http://www.freshports.org/sysutils/fusefs-kmod/
.. _FUSE4X: http://fuse4x.org/
