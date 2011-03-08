#!/usr/bin/env python
'''
setup.py

Installation script for LLFUSE.

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of LLFUSE (http://python-llfuse.googlecode.com).
LLFUSE can be distributed under the terms of the GNU LGPL.
'''

from __future__ import division, print_function, absolute_import

import sys
import os
import subprocess

# Add util to load path
basedir = os.path.abspath(os.path.dirname(sys.argv[0]))
sys.path.insert(0, os.path.join(basedir, 'util'))

# Add src to load path, important for Sphinx autodoc
# to work properly
sys.path.insert(0, os.path.join(basedir, 'src'))

# Import distribute
from distribute_setup import use_setuptools
use_setuptools(version='0.6.12', download_delay=5)
import setuptools
from setuptools import Extension


LLFUSE_VERSION = '0.30'

def main():
    
    with open(os.path.join(basedir, 'rst', 'about.rst'), 'r') as fh:
        long_desc = fh.read()

    compile_args = pkg_config('fuse', cflags=True, ldflags=False, min_ver='2.8.0')
    compile_args.extend(['-DFUSE_USE_VERSION=28',
                         '-DLLFUSE_VERSION="%s"' % LLFUSE_VERSION,
                         '-Werror', '-Wall', '-Wextra', '-Wconversion',
                         '-Wno-unused-parameter', '-Wno-sign-conversion' ])
    if sys.version_info[0] == 2:
        # http://bugs.python.org/issue969718
        compile_args.append('-fno-strict-aliasing')

    if sys.version_info[0] == 3 and sys.version_info[1] < 2:
        # http://bugs.python.org/issue7576
        compile_args.append('-Wno-missing-field-initializers')
        
    link_args = pkg_config('fuse', cflags=False, ldflags=True, min_ver='2.8.0')

    uname = subprocess.Popen(["uname", "-s"], stdout=subprocess.PIPE).communicate()[0].strip()
    uname = uname.decode('utf-8')
    if uname == 'Linux':
        compile_args.append('-DHAVE_STRUCT_STAT_ST_ATIM')
    elif uname == 'FreeBSD':
        compile_args.append('-DHAVE_STRUCT_STAT_ST_ATIMESPEC')
    else:
        print("NOTE: unknown system (%s), " % uname +
              "nanosecond resolution file times will not be available")

    setuptools.setup(
          name='llfuse',
          zip_safe=True,
          version=LLFUSE_VERSION,
          description='Python bindings for the low-level FUSE API',
          long_description=long_desc,
          author='Nikolaus Rath',
          author_email='Nikolaus@rath.org',
          url='http://python-llfuse.googlecode.com/',
          download_url='http://code.google.com/p/python-llfuse/downloads/',
          license='LGPL',
          classifiers=['Development Status :: 4 - Beta',
                       'Intended Audience :: Developers',
                       'Programming Language :: Python',
                       'Topic :: Software Development :: Libraries :: Python Modules',
                       'Topic :: System :: Filesystems',
                       'License :: OSI Approved :: GNU Library or Lesser General Public License (LGPL)',
                       'Operating System :: POSIX' ],
          platforms=[ 'POSIX', 'UNIX', 'Linux' ],
          keywords=['FUSE', 'python' ],
          package_dir={'': 'src'},
          packages=setuptools.find_packages('src'),
          provides=['llfuse'],
          ext_modules=[Extension('llfuse', ['src/llfuse.c'], 
                                  extra_compile_args=compile_args,
                                  extra_link_args=link_args)],
          cmdclass={'build_cython': build_cython,
                    'upload_docs': upload_docs },
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
        raise SystemExit('Failed to execute pkg-config. Exit code: %d.\n'
                         'Check that the %s development package been installed properly.'
                         % (proc.returncode, pkg))

    return cflags.decode('us-ascii').split()

        
class build_cython(setuptools.Command):
    user_options = []
    boolean_options = []
    description = "Compile .pyx to .c"

    def initialize_options(self):
        pass

    def finalize_options(self):
        # Attribute defined outside init
        #pylint: disable=W0201
        self.extensions = self.distribution.ext_modules

    def run(self):
        try:
            from Cython.Compiler.Main import compile as cython_compile
        except ImportError:
            raise SystemExit('Cython needs to be installed for this command')

        options = { 'include_path': [ os.path.join(basedir, 'Include') ],
                    'recursive': False, 'verbose': True,
                    'timestamps': False,
                    'compiler_directives': { 'embedsignature': True }
                     }
        
        for extension in self.extensions:
            for file_ in extension.sources:
                (file_, ext) = os.path.splitext(file_)
                path = os.path.join(basedir, file_)
                if ext != '.c':
                    continue 
                if os.path.exists(path + '.pyx'):
                    print('compiling %s to %s' % (file_ + '.pyx', file_ + ext))
                    res = cython_compile(path + '.pyx', full_module_name=extension.name,
                                         **options)
                    if res.num_errors != 0:
                        raise SystemExit('Cython encountered errors.')
                else:
                    print('%s is up to date' % (file_ + ext,))


        
class upload_docs(setuptools.Command):
    user_options = []
    boolean_options = []
    description = "Upload documentation"

    def initialize_options(self):
        pass

    def finalize_options(self):
        pass

    def run(self):
        subprocess.check_call(['rsync', '-aHv', '--del', os.path.join(basedir, 'doc', 'html') + '/',
                               'ebox.rath.org:/var/www/llfuse-docs/'])


if __name__ == '__main__':
    main()
