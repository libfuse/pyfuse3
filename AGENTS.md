# CLAUDE.md

This file provides guidance to AI Agents when working with code in this repository.

## Project Overview

pyfuse3 is a Python 3 binding for libfuse 3 that provides an asynchronous API compatible with Trio and asyncio. It enables writing full-featured Linux and macOS filesystems in Python.

**Development Status**: Stable when used with Trio. The project is in maintenance mode - bugs are fixed and compatibility with new Python/libfuse versions is maintained, but no new features are planned. Pull requests for improvements may be accepted.

## Build System

This project uses a **custom build backend** (`util/build_backend.py`) that wraps setuptools.build_meta. The build system:

- Dynamically configures Cython extensions based on pkg-config output and platform detection
- Requires libfuse3 >= 3.2.0 (checked via pkg-config)
- Platform-specific: -lrt on Linux, `-DFUSE_DARWIN_ENABLE_EXTENSIONS=0` on macOS (pyfuse3 uses
  the vanilla libfuse API of macFUSE, not its Darwin-specific variant)
- Uses Cython to compile `.pyx` files to C extensions

## Development Setup

Install development environment:
```bash
uv sync
. .venv/bin/activate
```

## Essential Commands

### Testing
```bash
# Run all tests
pytest test/

# Run specific test file
pytest test/test_api.py

# Run specific test
pytest test/test_api.py::test_something

# Enable debug logging from specific module
pytest --logdebug=pyfuse3 test/

# Enable all debug logging
pytest --logdebug=all test/
```

### Pre-completion checks
```bash
# Run in this order, fixing issues before proceeding to next tool:
pyright
mypy
ruff check --fix
ruff format
pytest --tb=short - test/
sphinx-build -W --keep-going -b html rst doc/html
```

### Documentation
```bash
# Build HTML documentation
sphinx-build -b html rst doc/html
```

## Code Architecture

### Hybrid Cython/Python Implementation

The core is split between Cython (performance-critical FUSE bindings) and pure Python (high-level operations):

- **`src/pyfuse3/__init__.pyx`**: Main Cython module containing C bindings to libfuse3
  - Includes `.pxi` files: `handlers.pxi` (FUSE request handlers), `internal.pxi`, `macros.pxd`
  - Compiled to `__init__.cpython-*.so` C extension
  - Exports classes: `FUSEError`, `EntryAttributes`, `FileInfo`, `RequestContext`, `SetattrFields`, `StatvfsData`
  - Core functions: `init()`, `main()`, `close()`, `invalidate_inode()`, `readdir_reply()`

- **`src/pyfuse3/_pyfuse3.py`**: Pure-Python components
  - Defines `Operations` base class with all FUSE handler methods (lookup, getattr, read, write, etc.)
  - Type definitions: `FileHandleT`, `FileNameT`, `InodeT`, `ModeT`, `XAttrNameT`
  - `async_wrapper()` function ensures Trio coroutines are pure-Python

- **`src/pyfuse3/asyncio.py`**: asyncio compatibility layer (less tested than Trio)

- **`src/pyfuse3/__init__.pyi`**: Type stubs for external API

### FUSE Operations Pattern

Filesystems are implemented by subclassing `Operations` and overriding async handler methods:
- All handlers are async (Trio-based by default)
- Handlers must raise `FUSEError(errno)` for errors, never return `None` for errors
- Unimplemented handlers should raise `FUSEError(errno.ENOSYS)` to let kernel handle them
- The `Operations` class has configuration flags: `supports_dot_lookup`, `enable_writeback_cache`, `enable_acl`

### Request Flow
1. FUSE kernel module calls C handlers in `handlers.pxi`
2. C handlers queue requests and pass to Python via Trio
3. Python `Operations` handlers process requests asynchronously
4. Results flow back through C bindings to FUSE kernel

### Testing Architecture

- **`test/conftest.py`**: pytest configuration with custom plugin `pytest_checklogs`
  - Validates no unexpected warnings/errors in logs
  - `--installed` flag to test installed vs development version
  - `--logdebug` for module-specific debug output
  - Adds 1-second delay after test failure to capture server output

- **`test/util.py`**: Test utilities for mounting/unmounting filesystems

- **Filesystem tests**: Run filesystem in separate process using multiprocessing (fork context required)

## Project Structure

```
src/pyfuse3/
  __init__.pyx          # Main Cython module (FUSE bindings)
  __init__.pyi          # Type stubs
  _pyfuse3.py           # Pure-Python Operations class
  asyncio.py            # asyncio compatibility
  handlers.pxi          # FUSE request handlers (included by __init__.pyx)
  internal.pxi          # Internal Cython utilities
  macros.pxd            # Cython macro definitions
  *.c, *.h              # Small C helpers with platform-specific code (xattr.h, syncfs.h, ...)

examples/
  hello.py              # Simple example with Trio
  hello_asyncio.py      # Simple example with asyncio
  tmpfs.py              # In-memory filesystem
  passthroughfs.py      # Passthrough filesystem proxy

test/
  conftest.py           # pytest configuration
  pytest_checklogs.py   # Custom pytest plugin for log validation
  util.py               # Test utilities
  test_*.py             # Test files

util/
  build_backend.py      # Custom PEP 517 build backend

developer-notes/
  setup.md              # Development setup instructions
```

## Type Annotations

- Type hints are mandatory for all functions and methods
- The project includes `py.typed` marker for external type checking
- Uses `NewType` for semantic types: `InodeT`, `FileHandleT`
- Pyright mode: `standard`
- Mypy: `check_untyped_defs = true`

## Platform Support

- **Linux**: Primary platform, fully supported
- **macOS**: Supported via macFUSE's libfuse3 (see `rst/platforms.rst` for the differences, e.g.
  no readdirplus, so pyfuse3 falls back to plain readdir; the FUSE fd cannot be used with kqueue,
  so a helper thread waits for it with select(2))
- **FreeBSD**: Limited support via PLATFORM_BSD detection
