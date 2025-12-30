# Define the pyfuse3 Cython extension module

inc_dirs = include_directories('../Include', 'pyfuse3')

compile_args = [
  '-DFUSE_USE_VERSION=32',
  '-Wall',
  '-Wextra',
  '-Wconversion',
  '-Wsign-compare',
  '-Wno-unused-function',
  '-Wno-implicit-fallthrough',
  '-Wno-unused-parameter',
]

link_args = ['-lpthread']
sources = ['pyfuse3/__init__.pyx']

# Platform-specific configuration
if host_system == 'darwin'
  sources += ['pyfuse3/darwin_compat.c']
elif host_system == 'linux' or host_system == 'gnu'
  link_args += ['-lrt']
endif

pyfuse3_ext = py.extension_module(
  '__init__',
  sources: sources,
  include_directories: inc_dirs,
  c_args: compile_args,
  link_args: link_args,
  dependencies: fuse3_dep,
  install: true,
  subdir: 'pyfuse3',
  override_options: ['cython_language=c'],
  cython_args: ['-I', meson.project_source_root() / 'Include'],
)

# Install pure Python modules
py.install_sources(
  [
    'pyfuse3/__init__.pyi',
    'pyfuse3/_pyfuse3.py',
    'pyfuse3/asyncio.py',
    'pyfuse3/py.typed',
  ],
  preserve_path: true,
)
