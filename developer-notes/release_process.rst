Steps for Releasing a New Version
---------------------------------

 * Bump version in `setup.py`
 * Add release date to `Changes.txt`
 * Check `hg status -u`, if necessary run `hg purge` to avoid undesired files in the tarball.
 * `./setup.py build_cython`
 * `./setup.py sdist`
 * Extract tarball in temporary directory,
    * `python3 setup.py build_ext --inplace && python3 -m pytest test`
    * Run tests under valgrind. Build python `--with-valgrind --with-pydebug`, then `valgrind --trace-children=yes "--trace-children-skip=*mount*" python-dbg -m pytest test/`
    * `./setup.py build_sphinx`
    * `./setup.py upload_docs` 
 * `./setup.py sdist upload --sign`
 * Git commit, git tag
