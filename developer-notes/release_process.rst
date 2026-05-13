Steps for Releasing a New Version
---------------------------------

1. Start a new changeset

2. Go through commits since last release, and document user-visible changes in
  `Changes.rst`. Decide on an appropriate version number, and add the corresponding
   release heading (The version number in this heading is what the release
   script will use.).

3. Make sure ``$PYFUSE_SIGNING_KEYS_DIR`` points at the directory holding the
   signify secret keys (containing at minimum ``pyfuse-next.sec`` and
   ``pyfuse-<current-major>.sec``).

4. Run ``util/make_release.py``. The script:

   * rotates the signify keys when the new version starts a new minor or
     major release (otherwise it reuses the existing key for bugfix releases),
   * commits ``Changes.rst`` as ``Released <X.Y.Z>`` and tags ``v<X.Y.Z>``,
   * builds the HTML docs and the sdist via ``uv``,
   * signs the sdist with ``signify``,
   * writes an announcement template 

5. Upload to PyPI: ``uv run twine upload dist/pyfuse3-<X.Y.Z>.tar.gz``.

6. Push to GitHub: ``git push && git push --tags``.

7. Create a release on GitHub at
   https://github.com/libfuse/pyfuse3/releases/.

8. Send the announcement to the FUSE mailing list.
