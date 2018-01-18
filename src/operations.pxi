# -*- coding: utf-8 -*-
'''
operations.pxi

Copyright © 2013 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
'''

class Operations(object):
    '''
    This class defines the general and request handler methods that an
    Python-LLFUSE file system may implement. If a particular request handler has
    not been implemented, it must raise `FUSEError` with an errorcode of
    `errno.ENOSYS`. Further requests of this type will then be handled directly
    by the FUSE kernel module without calling the handler again.

    The only exception that request handlers are allowed to raise is
    `FUSEError`. This will cause the specified errno to be returned by the
    syscall that is being handled.

    It is recommended that file systems are derived from this class and only
    overwrite the handlers that they actually implement. (The methods defined in
    this class all just raise ``FUSEError(ENOSYS)`` or do nothing).
    '''

    def init(self):
        '''Initialize operations

        This method will be called just before the file system starts handling
        requests. It must not raise any exceptions (not even `FUSEError`), since
        it is not handling a particular client request.
        '''

        pass

    def destroy(self):
        '''Clean up operations.

        This method will be called when `llfuse.close` has been called and the
        file system is about to be unmounted.

        This method must not raise any exceptions (not even `FUSEError`), since
        it is not handling a particular client request.
        '''

        pass

    def lookup(self, parent_inode, name, ctx):
        '''Look up a directory entry by name and get its attributes.

        This method should return an `EntryAttributes` instance for the
        directory entry *name* in the directory with inode *parent_inode*.

        If there is no such entry, the method should either return an
        `EntryAttributes` instance with zero ``st_ino`` value (in which case
        the negative lookup will be cached as specified by ``entry_timeout``),
        or it should raise `FUSEError` with an errno of `errno.ENOENT` (in this
        case the negative result will not be cached).

        *ctx* will be a `RequestContext` instance.

        The file system must be able to handle lookups for :file:`.` and
        :file:`..`, no matter if these entries are returned by `readdir` or not.

        (Successful) execution of this handler increases the lookup count for
        the returned inode by one.
        '''

        raise FUSEError(errno.ENOSYS)

    def forget(self, inode_list):
        '''Decrease lookup counts for inodes in *inode_list*

        *inode_list* is a list of ``(inode, nlookup)`` tuples. This method
        should reduce the lookup count for each *inode* by *nlookup*.

        If the lookup count reaches zero, the inode is currently not known to
        the kernel. In this case, the file system will typically check if there
        are still directory entries referring to this inode and, if not, remove
        the inode.

        If the file system is unmounted, it may not have received `forget` calls
        to bring all lookup counts to zero. The `destroy` method should be used
        to clean up inodes that at that point still have non-zero lookup count
        (e.g. by calling `forget` with the current lookup count for every such
        inode).

        This method must not raise any exceptions (not even `FUSEError`), since
        it is not handling a particular client request.
        '''

        pass

    def getattr(self, inode, ctx):
        '''Get attributes for *inode*

        *ctx* will be a `RequestContext` instance.

        This method should return an `EntryAttributes` instance with the
        attributes of *inode*. The `~EntryAttributes.entry_timeout` attribute is
        ignored in this context.
        '''

        raise FUSEError(errno.ENOSYS)


    def setattr(self, inode, attr, fields, fh, ctx):
        '''Change attributes of *inode*

        *fields* will be an `SetattrFields` instance that specifies which
        attributes are to be updated. *attr* will be an `EntryAttributes`
        instance for *inode* that contains the new values for changed
        attributes, and undefined values for all other attributes.

        Most file systems will additionally set the
        `~EntryAttributes.st_ctime_ns` attribute to the current time (to
        indicate that the inode metadata was changed).

        If the syscall that is being processed received a file descriptor
        argument (like e.g. :manpage:`ftruncate(2)` or :manpage:`fchmod(2)`),
        *fh* will be the file handle returned by the corresponding call to the
        `open` handler. If the syscall was path based (like
        e.g. :manpage:`truncate(2)` or :manpage:`chmod(2)`), *fh* will be
        `None`.

        *ctx* will be a `RequestContext` instance.

        The method should return an `EntryAttributes` instance (containing both
        the changed and unchanged values).
        '''

        raise FUSEError(errno.ENOSYS)

    def readlink(self, inode, ctx):
        '''Return target of symbolic link *inode*.

        *ctx* will be a `RequestContext` instance.
        '''

        raise FUSEError(errno.ENOSYS)


    def mknod(self, parent_inode, name, mode, rdev, ctx):
        '''Create (possibly special) file

        This method must create a (special or regular) file *name* in the
        directory with inode *parent_inode*. Whether the file is special or
        regular is determined by its *mode*. If the file is neither a block nor
        character device, *rdev* can be ignored. *ctx* will be a
        `RequestContext` instance.

        The method must return an `EntryAttributes` instance with the attributes
        of the newly created directory entry.

        (Successful) execution of this handler increases the lookup count for
        the returned inode by one.
       '''

        raise FUSEError(errno.ENOSYS)

    def mkdir(self, parent_inode, name, mode, ctx):
        '''Create a directory

        This method must create a new directory *name* with mode *mode* in the
        directory with inode *parent_inode*. *ctx* will be a `RequestContext`
        instance.

        This method must return an `EntryAttributes` instance with the
        attributes of the newly created directory entry.

        (Successful) execution of this handler increases the lookup count for
        the returned inode by one.
        '''

        raise FUSEError(errno.ENOSYS)

    def unlink(self, parent_inode, name, ctx):
        '''Remove a (possibly special) file

        This method must remove the (special or regular) file *name* from the
        direcory with inode *parent_inode*.  *ctx* will be a `RequestContext`
        instance.

        If the inode associated with *file* (i.e., not the *parent_inode*) has a
        non-zero lookup count, or if there are still other directory entries
        referring to this inode (due to hardlinks), the file system must remove
        only the directory entry (so that future calls to `readdir` for
        *parent_inode* will no longer include *name*, but e.g. calls to
        `getattr` for *file*'s inode still succeed). (Potential) removal of the
        associated inode with the file contents and metadata must be deferred to
        the `forget` method to be carried out when the lookup count reaches zero
        (and of course only if at that point there are no more directory entries
        associated with the inode either).

        '''

        raise FUSEError(errno.ENOSYS)

    def rmdir(self, parent_inode, name, ctx):
        '''Remove directory *name*

        This method must remove the directory *name* from the direcory with
        inode *parent_inode*. *ctx* will be a `RequestContext` instance. If
        there are still entries in the directory, the method should raise
        ``FUSEError(errno.ENOTEMPTY)``.

        If the inode associated with *name* (i.e., not the *parent_inode*) has a
        non-zero lookup count, the file system must remove only the directory
        entry (so that future calls to `readdir` for *parent_inode* will no
        longer include *name*, but e.g. calls to `getattr` for *file*'s inode
        still succeed). Removal of the associated inode holding the directory
        contents and metadata must be deferred to the `forget` method to be
        carried out when the lookup count reaches zero.

        (Since hard links to directories are not allowed by POSIX, this method
        is not required to check if there are still other directory entries
        refering to the same inode. This conveniently avoids the ambigiouties
        associated with the ``.`` and ``..`` entries).
        '''

        raise FUSEError(errno.ENOSYS)

    def symlink(self, parent_inode, name, target, ctx):
        '''Create a symbolic link

        This method must create a symbolink link named *name* in the directory
        with inode *parent_inode*, pointing to *target*.  *ctx* will be a
        `RequestContext` instance.

        The method must return an `EntryAttributes` instance with the attributes
        of the newly created directory entry.

        (Successful) execution of this handler increases the lookup count for
        the returned inode by one.
        '''

        raise FUSEError(errno.ENOSYS)

    def rename(self, parent_inode_old, name_old, parent_inode_new,
               name_new, ctx):
        '''Rename a directory entry.

        This method must rename *name_old* in the directory with inode
        *parent_inode_old* to *name_new* in the directory with inode
        *parent_inode_new*.  If *name_new* already exists, it should be
        overwritten.  *ctx* will be a `RequestContext` instance.

        Let the inode associated with *name_old* in *parent_inode_old* be
        *inode_moved*, and the inode associated with *name_new* in
        *parent_inode_new* (if it exists) be called *inode_deref*.

        If *inode_deref* exists and has a non-zero lookup count, or if there are
        other directory entries referring to *inode_deref*), the file system
        must update only the directory entry for *name_new* to point to
        *inode_moved* instead of *inode_deref*.  (Potential) removal of
        *inode_deref* (containing the previous contents of *name_new*) must be
        deferred to the `forget` method to be carried out when the lookup count
        reaches zero (and of course only if at that point there are no more
        directory entries associated with *inode_deref* either).
        '''

        raise FUSEError(errno.ENOSYS)

    def link(self, inode, new_parent_inode, new_name, ctx):
        '''Create directory entry *name* in *parent_inode* refering to *inode*.

        *ctx* will be a `RequestContext` instance.

        The method must return an `EntryAttributes` instance with the
        attributes of the newly created directory entry.

        (Successful) execution of this handler increases the lookup count for
        the returned inode by one.
        '''

        raise FUSEError(errno.ENOSYS)

    def open(self, inode, flags, ctx):
        '''Open a inode *inode* with *flags*.

        *ctx* will be a `RequestContext` instance.

        *flags* will be a bitwise or of the open flags described in the
        :manpage:`open(2)` manpage and defined in the `os` module (with the
        exception of ``O_CREAT``, ``O_EXCL``, ``O_NOCTTY`` and ``O_TRUNC``)

        This method must return an integer file handle. The file handle will be
        passed to the `read`, `write`, `flush`, `fsync` and `release` methods to
        identify the open file.
        '''

        raise FUSEError(errno.ENOSYS)

    def read(self, fh, off, size):
        '''Read *size* bytes from *fh* at position *off*

        *fh* will by an integer filehandle returned by a prior `open` or
        `create` call.

        This function should return exactly the number of bytes requested except
        on EOF or error, otherwise the rest of the data will be substituted with
        zeroes.
        '''

        raise FUSEError(errno.ENOSYS)

    def write(self, fh, off, buf):
        '''Write *buf* into *fh* at *off*

        *fh* will by an integer filehandle returned by a prior `open` or
        `create` call.

        This method must return the number of bytes written. However, unless the
        file system has been mounted with the ``direct_io`` option, the file
        system *must* always write *all* the provided data (i.e., return
        ``len(buf)``).
        '''

        raise FUSEError(errno.ENOSYS)

    def flush(self, fh):
        '''Handle close() syscall.

        *fh* will by an integer filehandle returned by a prior `open` or
        `create` call.

        This method is called whenever a file descriptor is closed. It may be
        called multiple times for the same open file (e.g. if the file handle
        has been duplicated).
        '''

        raise FUSEError(errno.ENOSYS)

    def release(self, fh):
        '''Release open file

        This method will be called when the last file descriptor of *fh* has
        been closed, i.e. when the file is no longer opened by any client
        process.

        *fh* will by an integer filehandle returned by a prior `open` or
        `create` call. Once `release` has been called, no future requests for
        *fh* will be received (until the value is re-used in the return value of
        another `open` or `create` call).

        This method may return an error by raising `FUSEError`, but the error
        will be discarded because there is no corresponding client request.
        '''

        raise FUSEError(errno.ENOSYS)

    def fsync(self, fh, datasync):
        '''Flush buffers for open file *fh*

        If *datasync* is true, only the file contents should be
        flushed (in contrast to the metadata about the file).

        *fh* will by an integer filehandle returned by a prior `open` or
        `create` call.
        '''

        raise FUSEError(errno.ENOSYS)

    def opendir(self, inode, ctx):
        '''Open the directory with inode *inode*

        *ctx* will be a `RequestContext` instance.

        This method should return an integer file handle. The file handle will
        be passed to the `readdir`, `fsyncdir` and `releasedir` methods to
        identify the directory.
        '''

        raise FUSEError(errno.ENOSYS)


    def readdir(self, fh, off):
        '''Read entries in open directory *fh*.

        This method should return an iterator over the contents of directory
        *fh* (as returned by a prior `opendir` call), starting at the entry
        identified by *off*.

        The iterator must yield tuples of the form :samp:`({name}, {attr},
        {next_})`, where *attr* is an `EntryAttributes` instance and *next_*
        gives an offset that can be passed as *off* to start a successive
        `readdir` call at the right position.

        Iteration may be stopped as soon as enough elements have been
        retrieved. The method should be prepared for this case.

        If entries are added or removed during a `readdir` cycle, they may or
        may not be returned. However, they must not cause other entries to be
        skipped or returned more than once.

        :file:`.` and :file:`..` entries may be included but are not required.
        '''

        raise FUSEError(errno.ENOSYS)

    def releasedir(self, fh):
        '''Release open directory

        This method will be called exactly once for each `opendir` call. After
        *fh* has been released, no further `readdir` requests will be received
        for it (until it is opened again with `opendir`).
        '''

        raise FUSEError(errno.ENOSYS)

    def fsyncdir(self, fh, datasync):
        '''Flush buffers for open directory *fh*

        If *datasync* is true, only the directory contents should be
        flushed (in contrast to metadata about the directory itself).
        '''

        raise FUSEError(errno.ENOSYS)

    def statfs(self, ctx):
        '''Get file system statistics

        *ctx* will be a `RequestContext` instance.

        The method must return an appropriately filled `StatvfsData` instance.
        '''

        raise FUSEError(errno.ENOSYS)

    def stacktrace(self):
        '''Asynchronous debugging

        This method will be called when the ``fuse_stacktrace`` extended
        attribute is set on the mountpoint. It will be called without holding
        the global lock. The default implementation logs the current stack trace
        of every running Python thread. This can be quite useful to debug file
        system deadlocks.
        '''

        import sys
        import traceback

        code = list()
        for threadId, frame in sys._current_frames().items():
            code.append("\n# ThreadID: %s" % threadId)
            for filename, lineno, name, line in traceback.extract_stack(frame):
                code.append('%s:%d, in %s' % (os.path.basename(filename), lineno, name))
                if line:
                    code.append("    %s" % (line.strip()))

        log.error("\n".join(code))

    def setxattr(self, inode, name, value, ctx):
        '''Set extended attribute *name* of *inode* to *value*.

        *ctx* will be a `RequestContext` instance.

        The attribute may or may not exist already. Both *name* and *value* will
        be of type `bytes`. *name* is guaranteed not to contain zero-bytes
        (``\\0``).
        '''

        raise FUSEError(errno.ENOSYS)

    def getxattr(self, inode, name, ctx):
        '''Return extended attribute *name* of *inode*

        *ctx* will be a `RequestContext` instance.

        If the attribute does not exist, the method must raise `FUSEError` with
        an error code of `ENOATTR`. *name* will be of type `bytes`, but is
        guaranteed not to contain zero-bytes (``\\0``).
        '''

        raise FUSEError(errno.ENOSYS)

    def listxattr(self, inode, ctx):
        '''Get list of extended attributes for *inode*

        *ctx* will be a `RequestContext` instance.

        This method must return an iterator over a sequence of `bytes` objects.
        The objects must not to include zero-bytes (``\\0``).
        '''

        raise FUSEError(errno.ENOSYS)

    def removexattr(self, inode, name, ctx):
        '''Remove extended attribute *name* of *inode*

        *ctx* will be a `RequestContext` instance.

        If the attribute does not exist, the method must raise `FUSEError` with
        an error code of `ENOATTR`. *name* will be of type `bytes`, but is
        guaranteed not to contain zero-bytes (``\\0``).
        '''

        raise FUSEError(errno.ENOSYS)


    def access(self, inode, mode, ctx):
        '''Check if requesting process has *mode* rights on *inode*.

        *ctx* will be a `RequestContext` instance.

        The method must return a boolean value.

        If the ``default_permissions`` mount option is given, this method is not
        called.

        When implementing this method, the `get_sup_groups` function may be
        useful.
        '''

        raise FUSEError(errno.ENOSYS)

    def create(self, parent_inode, name, mode, flags, ctx):
        '''Create a file with permissions *mode* and open it with *flags*

        *ctx* will be a `RequestContext` instance.

        The method must return a tuple of the form *(fh, attr)*, where *fh* is a
        file handle like the one returned by `open` and *attr* is an
        `EntryAttributes` instance with the attributes of the newly created
        directory entry.

        (Successful) execution of this handler increases the lookup count for
        the returned inode by one.
        '''

        raise FUSEError(errno.ENOSYS)
