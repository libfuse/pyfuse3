Steps for Releasing a New Version
---------------------------------

 * `export NEWVER=XX.YY.Z`
 * Add release date and version to `Changes.rst`
 * `git commit --all -m "Released $NEWVER"`
 * `git tag v$NEWVER`
 * `uv sync --locked`
 * `uv run sphinx-build -b html rst doc/html`
 * `uv build --sdist`
 * `gpg --detach-sign --armor --output dist/pyfuse3-$NEWVER.tar.gz.asc dist/pyfuse3-$NEWVER.targ.nz` (or `util/sdist-sign $NEWVER`)
 * `uv run twine upload dist/pyfuse3-$NEWVER.tar.gz` (or `util/upload-pypi $NEWVER`)
 * Create release on GitHub (https://github.com/libfuse/pyfuse3/releases/)
 * Send announcement to mailing list
  * Get contributors: `git log --pretty="format:%an <%aE>" "${PREV_TAG}..v${NEWVER}" | sort -u`


Announcement template:
----------------------

Dear all,

I'm happy to announce a new release of pyfuse3, version <X.Y>.

pyfuse3 is a set of Python 3 bindings for `libfuse 3`_. It provides an
asynchronous API compatible with Trio_ and asyncio_, and enables you to easily
write a full-featured Linux filesystem in Python.

From the changelog:

<paste here>

The following people have contributed code to this release:

[PASTE HERE]

As usual, the newest release can be downloaded from PyPi at
https://pypi.python.org/pypi/pyfuse3/.

Please report any bugs on the issue tracker at
https://github.com/libfuse/pyfuse3/issues. For discussion and questions, please
use the general FUSE mailing list (i.e., this list) or the GitHub discussion
forum at https://github.com/libfuse/pyfuse3/discussions.
