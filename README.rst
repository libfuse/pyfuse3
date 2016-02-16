..
  NOTE: We cannot use sophisticated ReST syntax (like
  e.g. :file:`foo`) here because this isn't rendered correctly
  by PyPi and/or BitBucket.

The Python-LLFUSE Module
========================

.. start-intro

Python-LLFUSE is a set of Python bindings for the low level FUSE_
API. It requires at least FUSE 2.8.0 and supports both Python 2.x and
3.x. Like FUSE itself, Python-LLFUSE is developed for Linux
systems. However, we try to maintain compatibility with OS-X, FreeBSD
and NetBSD as well (but due to lack of pre-release testers we can't
guarantee that every Python-LLFUSE release will run on these
platforms - please report any bugs and we will try to fix them).

Python-LLFUSE releases can be downloaded from PyPi_. The documentation
can be `read online`__ and is also included in the ``doc/html``
directory of the Python-LLFUSE tarball.


Getting Help
------------

Please report any bugs on the `issue tracker`_. For discussion and
questions, please use the general `FUSE mailing list`_. A searchable
`mailing list archive`_ is kindly provided by Gmane_.

Development Status
------------------

The Python-LLFUSE API is not yet stable and may change from one
release to the other. Starting with version 0.42, Python-LLFUSE uses
semantic versioning. This means changes in the API will be reflected
in an increase of the major version number, i.e. the next
backwards-incompatible version will be 1.0. Projects designed for
e.g. version 0.42.1 of Python-LLFUSE are thus recommended to declare a
dependency on ``llfuse >= 0.42.1, < 1.0``.


Contributing
------------

The Python-LLFUSE source code is available both on GitHub_ and BitBucket_.

.. __: http://pythonhosted.org/llfuse/
.. _FUSE: http://github.com/libfuse/libfuse
.. _FUSE mailing list: https://lists.sourceforge.net/lists/listinfo/fuse-devel
.. _issue tracker: https://bitbucket.org/nikratio/python-llfuse/issues
.. _mailing list archive: http://dir.gmane.org/gmane.comp.file-systems.fuse.devel
.. _Gmane: http://www.gmane.org/
.. _PyPi: https://pypi.python.org/pypi/llfuse/
.. _BitBucket: https://bitbucket.org/nikratio/python-llfuse/
.. _GitHub: https://github.com/python-llfuse/main
