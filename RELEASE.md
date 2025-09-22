# Release Process for pyfuse3

This document describes the automated release process for pyfuse3.

## Overview

The project uses GitHub Actions to automatically build wheels and publish to PyPI when releases are created. The process supports:

- **Multi-platform wheel building** (Linux, macOS) using cibuildwheel
- **Automatic PyPI publishing** on GitHub releases
- **TestPyPI publishing** on main branch pushes
- **Source distribution building**

## Release Workflows

### 1. Build and Publish (`build-and-publish.yml`)

This workflow runs on:
- GitHub releases → Publishes to PyPI
- Pull requests → Builds wheels for testing

**Jobs:**
- `build_wheels`: Builds wheels for Linux and macOS using cibuildwheel
- `build_sdist`: Builds source distribution
- `publish_to_pypi`: Publishes to PyPI on releases (requires trusted publishing)
- `publish_to_testpypi`: Publishes to TestPyPI on main branch pushes

### 2. Release Creation (`release.yml`)

Automatically creates GitHub releases when version tags are pushed.

### 3. Testing (`test.yml`)

Runs the existing test suite across multiple Python versions.

## Making a Release

### Option 1: Using the Release Script

```bash
# Create a new release
python scripts/release.py 3.4.1

# Dry run to see what would happen
python scripts/release.py 3.4.1 --dry-run

# Update version without creating tag
python scripts/release.py 3.4.1 --no-tag
```

### Option 2: Manual Process

1. **Update version** in `setup.py`:
   ```python
   PYFUSE3_VERSION = '3.4.1'
   ```

2. **Commit and tag**:
   ```bash
   git add setup.py
   git commit -m "Bump version to 3.4.1"
   git tag -a v3.4.1 -m "Release 3.4.1"
   ```

3. **Push**:
   ```bash
   git push origin main
   git push origin v3.4.1
   ```

## Repository Setup Requirements

### GitHub Repository Settings

1. **Enable GitHub Actions** in repository settings

2. **Configure PyPI Trusted Publishing**:
   - Go to PyPI → Account Settings → Publishing
   - Add trusted publisher for your GitHub repository
   - Set environment name to `release`

3. **Configure TestPyPI Trusted Publishing** (optional):
   - Same process for test.pypi.org
   - Set environment name to `test-release`

4. **Create GitHub Environments**:
   - Go to repository Settings → Environments
   - Create `release` environment (for production releases)
   - Create `test-release` environment (for test releases)
   - Enable "Required reviewers" if desired

### Dependencies

The build process requires these system dependencies:
- **Linux**: `libfuse3-dev`, `pkg-config`
- **macOS**: `macfuse`, `pkg-config` (via Homebrew)

These are automatically installed by the workflow.

## Build Configuration

The build is configured via `pyproject.toml` using cibuildwheel:

- **Python versions**: 3.8, 3.9, 3.10, 3.11, 3.12, 3.13
- **Platforms**: Linux (x86_64), macOS (x86_64, arm64)
- **Skip**: 32-bit builds, musl Linux builds
- **Dependencies**: Automatically installs FUSE development libraries

## Testing

Each built wheel is tested by importing pyfuse3 to ensure basic functionality.

## Troubleshooting

### Build Failures

1. **FUSE dependency issues**: Check that system dependencies are properly installed
2. **Cython compilation**: Ensure Cython files are built before wheel creation
3. **Platform-specific issues**: Check cibuildwheel logs for platform-specific errors

### Publishing Failures

1. **Authentication**: Ensure trusted publishing is configured correctly
2. **Duplicate versions**: PyPI doesn't allow re-uploading the same version
3. **Environment protection**: Check GitHub environment settings

### Local Testing

Test the release process locally:

```bash
# Install cibuildwheel
pip install cibuildwheel

# Build wheels locally
python -m cibuildwheel --output-dir wheelhouse

# Test installation
pip install wheelhouse/*.whl
python -c "import pyfuse3; print('Success!')"
```

## Monitoring

- **GitHub Actions**: Monitor workflow runs in the Actions tab
- **PyPI**: Check package page for successful uploads
- **TestPyPI**: Verify test uploads work correctly
