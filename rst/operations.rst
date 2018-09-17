==================
 Request Handlers
==================

(You can use the :ref:`genindex` to directly jump to a specific handler).

.. currentmodule:: pyfuse3

.. autoclass:: Operations
  :members:

  .. attribute:: supports_dot_lookup = True

     If set, indicates that the filesystem supports lookup of the
     ``.`` and ``..`` entries. This is required if the file system
     will be shared over NFS.

  .. attribute:: enable_writeback_cache = True

     Enables write-caching in the kernel if available. This means that
     individual write request may be buffered and merged in the kernel
     before they are send to the filesystem.

  .. attribute:: enable_acl = False

     Enable ACL support. When enabled, the kernel will cache and have
     responsibility for enforcing ACLs. ACL will be stored as xattrs
     and passed to userspace, which is responsible for updating the
     ACLs in the filesystem, keeping the file mode in sync with the
     ACL, and ensuring inheritance of default ACLs when new filesystem
     nodes are created. Note that this requires that the file system
     is able to parse and interpret the xattr representation of ACLs.

      Enabling this feature implicitly turns on the
      ``default_permissions`` option.
