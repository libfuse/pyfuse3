#!/usr/bin/env python
#-*- coding: utf-8 -*-
'''
setup.py

Installation script for Python-LLFUSE.

Copyright © 2010 Nikolaus Rath <Nikolaus.org>

This file is part of Python-LLFUSE. This work may be distributed under
the terms of the GNU LGPL.
'''

from __future__ import division, print_function, absolute_import

import sys
import os
import subprocess
import warnings

# Disable Cython support in setuptools. It fails under some conditions
# (http://trac.cython.org/ticket/859), and we have our own build_cython command
# anyway.
try:
    import Cython.Distutils.build_ext
except ImportError:
    pass
else:
    # We can't delete Cython.Distutils.build_ext directly,
    # because the build_ext class (that is imported from
    # the build_ext module in __init__.py) shadows the
    # build_ext module.
    module = sys.modules['Cython.Distutils.build_ext']
    del module.build_ext

try:
    import setuptools
except ImportError:
    raise SystemExit('Setuptools package not found. Please install from '
                     'https://pypi.python.org/pypi/setuptools')
from setuptools import Extension

# Add util to load path
basedir = os.path.abspath(os.path.dirname(sys.argv[0]))
sys.path.insert(0, os.path.join(basedir, 'util'))

# When running from HG repo, enable all warnings
DEVELOPER_MODE = (os.path.exists(os.path.join(basedir, '.hg')) or
                  os.path.exists(os.path.join(basedir, '.git')))
if DEVELOPER_MODE:
    print('found hg or git repository, running in developer mode')
    warnings.simplefilter('default')

# Add src to load path, important for Sphinx autodoc
# to work properly
sys.path.insert(0, os.path.join(basedir, 'src'))

LLFUSE_VERSION = '0.41'

def main():

    try:
        from sphinx.application import Sphinx #pylint: disable-msg=W0612
    except ImportError:
        pass
    else:
        fix_docutils()

    with open(os.path.join(basedir, 'rst', 'about.rst'), 'r') as fh:
        long_desc = fh.read()

    compile_args = pkg_config('fuse', cflags=True, ldflags=False, min_ver='2.8.0')
    compile_args += ['-DFUSE_USE_VERSION=28', '-Wall', '-Wextra', '-Wconversion',
                     '-Wno-sign-conversion',
                     '-DLLFUSE_VERSION="%s"' % LLFUSE_VERSION]

    # Enable fatal warnings only when compiling from Mercurial tip.  (otherwise
    # we break forward compatibility because compilation with newer compiler may
    # fail if additional warnings are added)
    if DEVELOPER_MODE:
        compile_args.append('-Werror')

    # http://bugs.python.org/issue7576
    if sys.version_info[0] == 3 and sys.version_info[1] < 2:
        compile_args.append('-Wno-missing-field-initializers')

    # http://trac.cython.org/cython_trac/ticket/811
    compile_args.append('-Wno-unused-but-set-variable')

    # http://trac.cython.org/cython_trac/ticket/813
    compile_args.append('-Wno-maybe-uninitialized')

    # http://bugs.python.org/issue969718
    if sys.version_info[0] == 2:
        compile_args.append('-fno-strict-aliasing')

    link_args = pkg_config('fuse', cflags=False, ldflags=True, min_ver='2.8.0')
    link_args.append('-lpthread')

    if os.uname()[0] == 'Linux':
        link_args.append('-lrt')
        compile_args.append('-DHAVE_STRUCT_STAT_ST_ATIM')

    elif os.uname()[0] in ('Darwin', 'FreeBSD'):
        compile_args.append('-DHAVE_STRUCT_STAT_ST_ATIMESPEC')
    else:
        print("NOTE: unknown system (%s), nanosecond resolution file times "
              "will not be available" % os.uname()[0])

    setuptools.setup(
          name='llfuse',
          zip_safe=True,
          version=LLFUSE_VERSION,
          description='Python bindings for the low-level FUSE API',
          long_description=long_desc,
          author='Nikolaus Rath',
          author_email='Nikolaus@rath.org',
          url='https://bitbucket.org/nikratio/python-llfuse/',
          download_url='https://bitbucket.org/nikratio/python-llfuse/downloads',
          license='LGPL',
          classifiers=['Development Status :: 4 - Beta',
                       'Intended Audience :: Developers',
                       'Programming Language :: Python',
                       'Topic :: Software Development :: Libraries :: Python Modules',
                       'Topic :: System :: Filesystems',
                       'License :: OSI Approved :: GNU Library or Lesser General Public License (LGPL)',
                       'Operating System :: POSIX :: Linux',
                       'Operating System :: MacOS :: MacOS X',
                       'Operating System :: POSIX :: BSD :: FreeBSD'],
          platforms=[ 'Linux', 'FreeBSD', 'OS X' ],
          keywords=['FUSE', 'python' ],
          package_dir={'': 'src'},
          packages=setuptools.find_packages('src'),
          provides=['llfuse'],
          ext_modules=[Extension('llfuse.capi', ['src/llfuse/capi.c'],
                                  extra_compile_args=compile_args,
                                  extra_link_args=link_args)],
          cmdclass={'build_cython': build_cython },
          command_options={
            'build_sphinx': {
                'version': ('setup.py', LLFUSE_VERSION),
                'release': ('setup.py', LLFUSE_VERSION),
            }}
          )


def pkg_config(pkg, cflags=True, ldflags=False, min_ver=None):
    '''Frontend to ``pkg-config``'''

    if min_ver:
        cmd = ['pkg-config', pkg, '--atleast-version', min_ver ]

        if subprocess.call(cmd) != 0:
            cmd = ['pkg-config', '--modversion', pkg ]
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
            version = proc.communicate()[0].strip()
            if not version:
                raise SystemExit() # pkg-config generates error message already
            else:
                raise SystemExit('%s version too old (found: %s, required: %s)'
                                 % (pkg, version, min_ver))

    cmd = ['pkg-config', pkg ]
    if cflags:
        cmd.append('--cflags')
    if ldflags:
        cmd.append('--libs')

    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    cflags = proc.stdout.readline().rstrip()
    proc.stdout.close()
    if proc.wait() != 0:
        raise SystemExit() # pkg-config generates error message already

    return cflags.decode('us-ascii').split()


class build_cython(setuptools.Command):
    user_options = []
    boolean_options = []
    description = "Compile .pyx to .c"

    def initialize_options(self):
        pass

    def finalize_options(self):
        pass

    def run(self):
        try:
            from Cython.Compiler.Main import compile as cython_compile
            from Cython.Compiler import Options as DefaultOptions
        except ImportError:
            raise SystemExit('Cython needs to be installed for this command')

        # Cannot be passed directly to cython_compile()
        DefaultOptions.warning_errors = True
        DefaultOptions.fast_fail = True

        directives = dict()
        directives.update(DefaultOptions.extra_warnings)
        directives['embedsignature'] = True
        directives['language_level'] = 3

        # http://trac.cython.org/cython_trac/ticket/714
        directives['warn.maybe_uninitialized'] = False

        options = {'include_path': [ os.path.join(basedir, 'Include') ],
                   'verbose': True, 'timestamps': False, 'compile_time_env': {},
                   'compiler_directives': directives }

        for sysname in ('linux', 'freebsd', 'darwin'):
            print('compiling capi.pyx to capi_%s.c...' % (sysname,))
            options['compile_time_env']['TARGET_PLATFORM'] = sysname
            options['output_file'] = os.path.join(basedir, 'src', 'llfuse',
                                                  'capi_%s.c' % (sysname,))
            res = cython_compile(os.path.join(basedir, 'src', 'llfuse', 'capi.pyx'),
                                 full_module_name='llfuse.capi', **options)
            if res.num_errors != 0:
                raise SystemExit('Cython encountered errors.')


        # distutils doesn't know that capi.c #includes other files
        # and thus does not recompile unless we change the modification
        # date.
        os.utime(os.path.join(basedir, 'src', 'llfuse', 'capi.c'), None)

def fix_docutils():
    '''Work around https://bitbucket.org/birkenfeld/sphinx/issue/1154/'''

    import docutils.parsers
    from docutils.parsers import rst
    old_getclass = docutils.parsers.get_parser_class

    # Check if bug is there
    try:
        old_getclass('rst')
    except AttributeError:
        pass
    else:
        return

    def get_parser_class(parser_name):
        """Return the Parser class from the `parser_name` module."""
        if parser_name in ('rst', 'restructuredtext'):
            return rst.Parser
        else:
            return old_getclass(parser_name)
    docutils.parsers.get_parser_class = get_parser_class

    assert docutils.parsers.get_parser_class('rst') is rst.Parser

if __name__ == '__main__':
    main()
