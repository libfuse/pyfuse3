=================
 The global lock
=================

provides a global lock that can be used to explicitly control which
Python thread is running at a given time. (The GIL already enforces
that at most one Python thread is running, but it does not provide
means to control which thread that is).

