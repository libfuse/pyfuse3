.. _example file system:

======================
 Example File Systems
======================

pyfuse3 comes with several example file systems in the
:file:`examples` directory of the release tarball. For completeness,
these examples are also included here.

Single-file, Read-only File System
==================================

(shipped as :file:`examples/lltest.py`)

.. literalinclude:: ../examples/hello.py
   :linenos:
   :language: python

In-memory File System
=====================

(shipped as :file:`examples/tmpfs.py`)

.. literalinclude:: ../examples/tmpfs.py
   :linenos:
   :language: python


Passthrough / Overlay File System
=================================

(shipped as :file:`examples/passthroughfs.py`)

.. literalinclude:: ../examples/passthroughfs.py
   :linenos:
   :language: python
