==============
 Installation
==============

.. highlight:: sh


Dependencies
============

In order to build and run pyfuse3 you need the following software:

* Linux kernel 3.9 or newer.
* Version 3.3.0 or newer of the libfuse_ library, including development
  headers (typically distributions provide them in a *libfuse3-devel*
  or *libfuse3-dev* package).
* Python_ 3.8 or newer installed with development headers
* The Trio_ Python module, version 0.7 or newer.
* The `setuptools`_ Python module, version 1.0 or newer.
* the `pkg-config`_ tool
* the `attr`_ library
* A C compiler (only for building)

To run the unit tests, you will need

* The `py.test`_ Python module, version 3.3.0 or newer


Stable releases
===============

To install a stable pyfuse3 release:

1. Download and unpack the release tarball from https://pypi.python.org/pypi/pyfuse3/
2. Run ``python3 setup.py build_ext --inplace`` to build the C extension
3. Run ``python3 -m pytest test/`` to run a self-test. If this fails, ask
   for help on the `FUSE mailing list`_  or report a bug in the
   `issue tracker <https://bitbucket.org/nikratio/python-pyfuse3/issues>`_.
4. To install system-wide for all users, run ``sudo python setup.py
   install``. To install into :file:`~/.local`, run ``python3
   setup.py install --user``.


Development Version
===================

If you have checked out the unstable development version, a bit more
effort is required. You need to also have Cython_ (0.29 or newer) and
Sphinx_ installed, and the necessary commands are::

  python3 setup.py build_cython
  python3 setup.py build_ext --inplace
  python3 -m pytest test/
  sphinx-build -b html rst doc/html
  python3 setup.py install


.. _Cython: http://www.cython.org/
.. _Sphinx: http://sphinx.pocoo.org/
.. _Python: http://www.python.org/
.. _Trio: https://github.com/python-trio/trio
.. _FUSE mailing list: https://lists.sourceforge.net/lists/listinfo/fuse-devel
.. _`py.test`: https://pypi.python.org/pypi/pytest/
.. _libfuse: http://github.com/libfuse/libfuse
.. _attr: http://savannah.nongnu.org/projects/attr/
.. _`pkg-config`: http://www.freedesktop.org/wiki/Software/pkg-config
.. _setuptools: https://pypi.python.org/pypi/setuptools
