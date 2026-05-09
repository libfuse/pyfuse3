==============
 Installation
==============

.. highlight:: sh


Dependencies
============

As usual, Python dependencies are specified in :file:`pyproject.toml`. However, to build pyfuse3 you
also need the following additional dependencies installed on your system:

* libfuse_, version 3.3.0 or newer, including development
  headers (typically distributions provide them in a *libfuse3-devel*
  or *libfuse3-dev* package).
* the `pkg-config`_ tool
* the `attr`_ library
* Python development headers (for example, the *python3-dev* or
  *python3-devel* package on many Linux distributions)
* A C compiler


Stable releases
===============

To install a stable pyfuse3 release, ensure you have the non-Python dependencies
installed and then use your favorite Python package manager to install pyfuse3 from
PyPI (e.g. ``pip install pyfuse3``).

Pyfuse release tarballs are signed with
`signify <https://github.com/aperezdc/signify>`_. You can validate the signature with::

  signify -V -m pyfuse3-A.B.C.tar.gz -p <public-key>

The public key needs to be retrieved from a trustworthy source for the first installation.
Afterwards, the trust chain is self-sustaining: each release tarball contains the public key for the
release in its ``signify/`` directory. Bugfix releases (``A.B.C``) will be signed
by :file:`pyfuse-A.B.pub`. New major or minor releases (``A.B.0``) will be signed by
:file:`pyfuse-next.pub`.


Installing from Git / Developing pyfuse3
========================================

Clone the pyfuse3_ repository and take a look at :file:`developer_notes/setup.md`.



.. _libfuse: http://github.com/libfuse/libfuse
.. _attr: http://savannah.nongnu.org/projects/attr/
.. _`pkg-config`: http://www.freedesktop.org/wiki/Software/pkg-config
.. _pyfuse3: https://github.com/libfuse/pyfuse3/
