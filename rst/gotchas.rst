================
 Common Gotchas
================

.. currentmodule:: pyfuse3

This chapter lists some common gotchas that should be avoided.


Removing inodes in unlink handler
=================================

If your file system is mounted at :file:`mnt`, the following code
should complete without errors::

  with open('mnt/file_one', 'w+') as fh1:
      fh1.write('foo')
      fh1.flush()
      with open('mnt/file_one', 'a') as fh2:
          os.unlink('mnt/file_one')
          assert 'file_one' not in os.listdir('mnt')
          fh2.write('bar')
      os.close(os.dup(fh1.fileno()))
      fh1.seek(0)
      assert fh1.read() == 'foobar'

If you're getting an error, then you probably did a mistake when
implementing the `~Operations.unlink` handler and are removing the
file contents when you should be deferring removal to the
`~Operations.forget` handler.
