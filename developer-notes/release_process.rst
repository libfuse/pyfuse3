Steps for Releasing a New Version
---------------------------------

 * Bump version in `setup.py`
 * Add release date to `Changes.txt`
 * `./setup.py build_cython`
 * `./setup.py sdist`
 * Extract tarball in temporary directory,
    * `python3 setup.py build_ext --inplace && python3 -m pytest test`
    * Run tests under valgrind. Build python `--with-valgrind --with-pydebug`, then `valgrind --trace-children=yes "--trace-children-skip=*mount*" python-dbg -m pytest test/`
    * `./setup.py build_sphinx`
 * `./setup.py build_ext --inplace build_sphinx`
 * `./setup.py sdist --sign`
 * `python3 -m twine upload dist/<file>.gz`
 * `./setup.py upload_docs`
 * Git commit, git tag
 * Send announcement to mailing list
  * Get contributors: `git log --pretty="format:%an <%aE>" "${PREV_TAG}..${TAG}" | sort -u`


Announcement template:
----------------------

Dear all,

I'm happy to announce a new release of pyfuse3, version <X.Y>.

pyfuse3 is a set of Python 3 bindings for `libfuse 3`_. It provides an
asynchronous API compatible with Trio_ and asyncio_, and enables you
to easily write a full-featured Linux filesystem in Python.

From the changelog:

<paste here>

The following people have contributed code to this release:

[PASTE HERE]

As usual, the newest release can be downloaded from PyPi at
https://pypi.python.org/pypi/pyfuse3/.

Please report any bugs on the issue tracker at
https://github.com/libfuse/pyfuse3/issues.  For discussion and
questions, please use the general FUSE mailing list (i.e., this list).
