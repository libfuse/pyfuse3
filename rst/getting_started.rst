.. _getting_started:

=================
 Getting started
=================

A file system is implemented by subclassing the `llfuse.Operations`
class and implementing the various request handlers. An instance of
the this class must then be passed to `llfuse.init` to mount the file
system. To enter the request handling loop, run `llfuse.main`. This
function will return when the file system should be unmounted again,
which is done by calling `llfuse.close`.

For easier debugging, it is strongly recommended that applications
using llfuse also make use of the faulthandler_ module.

It is probably a good idea to look at the :ref:`example file system`
as well.

.. _faulthandler: http://docs.python.org/3/library/faulthandler.html
