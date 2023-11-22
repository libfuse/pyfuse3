.. _asyncio:

=================
 asyncio Support
=================

By default, pyfuse3 uses asynchronous I/O using Trio_ (and most of the
documentation assumes that you are using Trio). If you'd rather use
asyncio, import the *pyfuse3.asyncio* module (*pyfuse3_asyncio* in 3.3.0 and
earlier) and call its *enable()* function before using *pyfuse3*.
For example::

   import pyfuse3
   import pyfuse3.asyncio

   pyfuse3.asyncio.enable()

   # Use pyfuse3 as usual from here on.

.. _Trio: https://github.com/python-trio/trio
