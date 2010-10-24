===================
 Installing LLFUSE
===================

.. highlight:: sh

Stable releases
===============

LLFUSE can be installed like any other Python extension. Make sure
that you have the Python and FUSE development headers installed, then
download and extract the LLFUSE tarball and run ::

  sudo python setup.py install

or :: 

  python setup.py install --user

Note that LLFUSE requires at least FUSE 2.8.0 and Python 2.6.

Development Version
===================

If you have checked out the unstable development version from the
Mercurial repository, a bit more effort is required. You need to have
recent versions of Cython_ and Sphinx_ installed, and the necessary
commands are::

  python setup.py build_cython
  python setup.py build_ext --inplace
  python setup.py build_sphinx
  python setup.py install
  
  
.. _Cython: http://www.cython.org/
.. _Sphinx: http://sphinx.pocoo.org/
