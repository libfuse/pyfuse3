project('pyfuse3', 'c', 'cython',
  meson_version: '>= 1.1.0',
  version: run_command(
    [find_program('python3'), '-m', 'setuptools_scm'],
    check: true
  ).stdout().strip(),
  default_options: [
    'warning_level=2',
  ]
)

# Import Python module
py = import('python').find_installation(pure: false)

# Check for required dependencies via pkg-config
fuse3_dep = dependency('fuse3', version: '>=3.2.0')

# Platform detection
host_system = host_machine.system()

# Process subdirectories
subdir('src')
