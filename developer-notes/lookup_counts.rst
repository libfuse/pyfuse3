===========================================
 Move Lookup Count Management into PYFUSE3?
===========================================

It would be nice if PYFUSE3 could keep track of the lookup count
management. That way its users wouldn't need to worry about which
handlers increase the lookup count, and `forget` would only be called
when the lookup count reaches zero.


Unfortunately, this is only possible when serializing all Python
request handlers. The reason is the following:

If an application wants to distinguish between "active" and forgotten
inodes it generally wants to establish some internal lstate that
survives as long as the corresponding inode is active. However, in
order to maintain that state, it has to be protected by the same lock
as the lookup count. This makes it impossible to update the lookup
count in PYFUSE3 after the python handler method has returned.

Example::

  class WontWork:
      def lookup(self, name):
          inode = get_inode(name)
          lookup_count[inode] += 1 # for simplicity, assume this is atomic
          cache[inode] = get_state(inode)

      def forget(self, inode):
          lookup_count[inode] -= 1 # for simplicity, assume this is atomic
          if lookup_count[inode] == 0:
              del cache[inode]

      def open(self, inode):
          # This works, because lookup() must have returned before
          # open() can be called.
          assert lookup_count[inode] > 0

          # This won't work, because forget() may have been
          interrupted by lookup() # between `if` and `del`
          assert cache[inode]


  class WouldWork:
      def lookup(self, name):
          inode = get_inode(name)
          with lock(inode):
              lookup_count[inode] += 1
              cache[inode] = get_state(inode)

      def forget(self, inode):
          with lock(inode):
              lookup_count[inode] -= 1
              if lookup_count[inode] == 0:
                  del cache[inode]

      def open(self, inode):
          assert lookup_count[inode] > 0
          assert cache[inode]


A slightly less complex situation arises if the application does not
want to keep state, but is just using lookup counts to postpone inode
removal until `forget`. In this case, one correct implementation is::

  class SimpleOps:

      def lookup(self, name):
          inode = get_inode(name)
          with lookup_lock:
              lookup_count[inode] += 1

      def forget(self, inode):
          with lookup_lock:
              lookup_count[inode] -= 1
              if lookup_count[inode] > 0:
                  return
              del lookup_count[inode]

          self.maybe_remove_inode(inode)


      def maybe_remove_inode(self, inode):
          with lock(inode):
              if refcount_of(inode) > 0:
                  return

              if inode in lookup_count:
                  # may have been looked up before refcount became zero
                  return

              # Inode is not referenced by any directory entries (so it cannot be
              # looked up), and it is not known to the kernel (so it cannot be
              # passed to any other handlers).  The lock on inode is required not
              # just because increment/decrement of the reference count may not be
              # atomic, but also because an `unlink` handler may have already
              # decreased the reference count, but still want to do something with
              # the inode.
              delete_inode(inode)

      def unlink_entry(self, name):
          delete_name(name)
          inode = get_inode(name)
          with lock(inode):
              decr_refcount_for(inode)
          return inode

      def unlink(self, name):
          inode = self.unlink_entry(name)
          if inode not in lookup_count:
              self.maybe_remove_inode(inode)


Here, the operations that modify lookup_count as well as the complete
forget() function could be moved into pyfuse3. The price of this is
that the application can no longer tell for sure if an inode is known
to the kernel. This is a problem if e.g. inode numbers are generated
dynamically - without forget(), how does the file system know when it
can re-use an inode?


Therefore, I've decided not to implement this feature. Applications
have to keep track of the lookup count manually.
