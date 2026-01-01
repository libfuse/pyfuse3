"""
Custom build backend for pyfuse3.

This wraps setuptools.build_meta and dynamically configures the Cython
extension based on pkg-config output and platform detection.
"""

import os
import subprocess

from setuptools import Extension
from setuptools.build_meta import *  # noqa: F403


def pkg_config(pkg, cflags=True, ldflags=False, min_ver=None):
    """Frontend to pkg-config"""

    if min_ver:
        cmd = ['pkg-config', pkg, '--atleast-version', min_ver]

        if subprocess.call(cmd) != 0:
            cmd = ['pkg-config', '--modversion', pkg]
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
            version = proc.communicate()[0].strip()
            if not version:
                raise SystemExit(2)  # pkg-config generates error message already
            else:
                raise SystemExit(
                    '%s version too old (found: %s, required: %s)' % (pkg, version, min_ver)
                )

    cmd = ['pkg-config', pkg]
    if cflags:
        cmd.append('--cflags')
    if ldflags:
        cmd.append('--libs')

    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    cflags = proc.stdout.readline().rstrip()
    proc.stdout.close()
    if proc.wait() != 0:
        raise SystemExit(2)  # pkg-config generates error message already

    return cflags.decode('us-ascii').split()


def get_extension_modules():
    """Build the Cython extension with platform-specific configuration."""

    # Get fuse3 flags from pkg-config
    compile_args = pkg_config('fuse3', cflags=True, ldflags=False, min_ver='3.2.0')
    compile_args += [
        '-DFUSE_USE_VERSION=32',
        '-Wall',
        '-Wextra',
        '-Wconversion',
        '-Wsign-compare',
        '-Wno-unused-function',
        '-Wno-implicit-fallthrough',
        '-Wno-unused-parameter',
    ]

    link_args = pkg_config('fuse3', cflags=False, ldflags=True, min_ver='3.2.0')
    link_args.append('-lpthread')

    # Determine source files based on platform
    c_sources = ['src/pyfuse3/__init__.pyx']

    if os.uname()[0] in ('Linux', 'GNU/kFreeBSD'):
        link_args.append('-lrt')
    elif os.uname()[0] == 'Darwin':
        c_sources.append('src/pyfuse3/darwin_compat.c')

    return [
        Extension(
            'pyfuse3.__init__',
            c_sources,
            extra_compile_args=compile_args,
            extra_link_args=link_args,
            include_dirs=['Include'],
        )
    ]


# Override get_requires_for_build_wheel to ensure we have pkg-config available
def get_requires_for_build_wheel(config_settings=None):
    """Return build requirements."""
    from setuptools.build_meta import get_requires_for_build_wheel as orig

    return orig(config_settings)


# Hook into the build process
_orig_build_wheel = build_wheel  # noqa: F405
_orig_build_editable = build_editable if 'build_editable' in dir() else None  # noqa: F405
_orig_build_sdist = build_sdist  # noqa: F405


def build_wheel(wheel_directory, config_settings=None, metadata_directory=None):
    """Build wheel with dynamic extension configuration."""
    # Inject our extension modules into the distribution
    from setuptools import Distribution

    # Monkey-patch Distribution to include our extensions
    orig_init = Distribution.__init__

    def patched_init(self, attrs=None):
        if attrs is None:
            attrs = {}
        # Add our dynamically configured extension modules
        if 'ext_modules' not in attrs:
            attrs['ext_modules'] = get_extension_modules()
        orig_init(self, attrs)

    Distribution.__init__ = patched_init

    try:
        return _orig_build_wheel(wheel_directory, config_settings, metadata_directory)
    finally:
        Distribution.__init__ = orig_init


def build_editable(wheel_directory, config_settings=None, metadata_directory=None):
    """Build editable wheel with dynamic extension configuration."""
    if _orig_build_editable is None:
        raise NotImplementedError("build_editable not available")

    from setuptools import Distribution

    # Monkey-patch Distribution to include our extensions
    orig_init = Distribution.__init__

    def patched_init(self, attrs=None):
        if attrs is None:
            attrs = {}
        # Add our dynamically configured extension modules
        if 'ext_modules' not in attrs:
            attrs['ext_modules'] = get_extension_modules()
        orig_init(self, attrs)

    Distribution.__init__ = patched_init

    try:
        return _orig_build_editable(wheel_directory, config_settings, metadata_directory)
    finally:
        Distribution.__init__ = orig_init


def build_sdist(sdist_directory, config_settings=None):
    """Build source distribution."""
    # For sdist, we don't need to configure extensions
    return _orig_build_sdist(sdist_directory, config_settings)
