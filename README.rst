..
  NOTE: We cannot use sophisticated ReST syntax (like
  e.g. :file:`foo`) here because this isn't rendered correctly
  by PyPi.


The pyfuse3 Module
==================

.. start-intro

pyfuse3 is a set of Python 3 bindings for `libfuse 3`_. It provides an
asynchronous API compatible with Trio_ and asyncio_, and enables you
to easily write a full-featured Linux or macOS filesystem in Python.

pyfuse3 releases can be downloaded from PyPi_. The documentation
can be `read online`__ and is also included in the ``doc/html``
directory of the pyfuse3 tarball.


Getting Help
------------

Please report any bugs on the `issue tracker`_. For discussion and
questions, please use the general `FUSE mailing list`_ or 
`GitHub Discussions <https://github.com/libfuse/pyfuse3/discussions>`_.

Development Status
------------------

pyfuse3 is stable when used with Trio. The current maintainers ensure that bugs
are addressed and pyfuse3 continues to work with new Python and libfuse
versions. There is no plan to add new features or other non-bugfix work.
However, pull requests for new features or other improvements may be accepted.

Using pyfuse3 with asyncio (rather than Trio) support is less well tested,
there may be bugs, and some of them may not be easily fixable.

If you need a synchronous (non async) implementation, `mfusepy <https://github.com/mxmlnkn/mfusepy>`_
is a maintained alternative.


Contributing
------------

The pyfuse3 source code is available on GitHub_.


.. __: https://pyfuse3.readthedocs.io/
.. _`libfuse 3`: http://github.com/libfuse/libfuse
.. _FUSE mailing list: https://lists.sourceforge.net/lists/listinfo/fuse-devel
.. _issue tracker: https://github.com/libfuse/pyfuse3/issues
.. _mailing list archive: http://dir.gmane.org/gmane.comp.file-systems.fuse.devel
.. _Gmane: http://www.gmane.org/
.. _PyPi: https://pypi.python.org/pypi/pyfuse3/
.. _GitHub: https://github.com/libfuse/pyfuse3
.. _Trio: https://github.com/python-trio/trio
.. _asyncio: https://docs.python.org/3/library/asyncio.html
