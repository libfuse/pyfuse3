..
  NOTE: We cannot use sophisticated ReST syntax (like
  e.g. :file:`foo`) here because this isn't rendered correctly
  by PyPi and/or BitBucket.


Warning - no longer developed!
==============================

pyfuse3 is no longer actively developed and just receiving community-contributed
maintenance to keep it alive for some time.


The pyfuse3 Module
==================

.. start-intro

pyfuse3 is a set of Python 3 bindings for `libfuse 3`_. It provides an
asynchronous API compatible with Trio_ and asyncio_, and enables you
to easily write a full-featured Linux filesystem in Python.

pyfuse3 releases can be downloaded from PyPi_. The documentation
can be `read online`__ and is also included in the ``doc/html``
directory of the pyfuse3 tarball.


Getting Help
------------

Please report any bugs on the `issue tracker`_. For discussion and
questions, please use the general `FUSE mailing list`_. A searchable
`mailing list archive`_ is kindly provided by Gmane_.


Development Status
------------------

pyfuse3 is in beta. Bugs are likely.

pyfuse3 uses semantic versioning. This means backwards incompatible
changes in the API will be reflected in an increase of the major
version number.


Contributing
------------

The pyfuse3 source code is available on GitHub_.


.. __: https://pyfuse3.readthedocs.io/
.. _libfuse 3: http://github.com/libfuse/libfuse
.. _FUSE mailing list: https://lists.sourceforge.net/lists/listinfo/fuse-devel
.. _issue tracker: https://github.com/libfuse/pyfuse3/issues
.. _mailing list archive: http://dir.gmane.org/gmane.comp.file-systems.fuse.devel
.. _Gmane: http://www.gmane.org/
.. _PyPi: https://pypi.python.org/pypi/pyfuse3/
.. _GitHub: https://github.com/libfuse/pyfuse3
.. _Trio: https://github.com/python-trio/trio
.. _asyncio: https://docs.python.org/3/library/asyncio.html
