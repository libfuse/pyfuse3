#!/usr/bin/env python3
"""
Release script for pyfuse3

This script helps with version bumping and creating releases.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

def get_current_version():
    """Extract current version from setup.py"""
    setup_py = Path(__file__).parent.parent / "setup.py"
    with open(setup_py) as f:
        content = f.read()
    
    match = re.search(r"PYFUSE3_VERSION = ['\"]([^'\"]+)['\"]", content)
    if not match:
        raise ValueError("Could not find PYFUSE3_VERSION in setup.py")
    
    return match.group(1)

def update_version(new_version):
    """Update version in setup.py"""
    setup_py = Path(__file__).parent.parent / "setup.py"
    
    with open(setup_py) as f:
        content = f.read()

    content = re.sub(
        r"PYFUSE3_VERSION = ['\"]([^'\"]+)['\"]",
        f"PYFUSE3_VERSION = '{new_version}'",
        content
    )
    
    with open(setup_py, 'w') as f:
        f.write(content)
    
    print(f"Updated version to {new_version} in setup.py")

def create_git_tag(version):
    """Create and push git tag"""
    tag = f"v{version}"
    
    try:
        subprocess.run(["git", "add", "setup.py"], check=True)
        subprocess.run(["git", "commit", "-m", f"Bump version to {version}"], check=True)
        
        # Create tag
        subprocess.run(["git", "tag", "-a", tag, "-m", f"Release {version}"], check=True)
        
        print(f"Created tag {tag}")
        print(f"To push the release, run: git push origin main && git push origin {tag}")
        
    except subprocess.CalledProcessError as e:
        print(f"Error creating tag: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Release script for pyfuse3")
    parser.add_argument("version", help="New version number (e.g., 3.4.1)")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be done without doing it")
    parser.add_argument("--no-tag", action="store_true", help="Don't create git tag")
    
    args = parser.parse_args()
    
    current_version = get_current_version()
    print(f"Current version: {current_version}")
    print(f"New version: {args.version}")
    
    if args.dry_run:
        print("DRY RUN: Would update version and create tag")
        return

    response = input("Continue? [y/N]: ")
    if response.lower() != 'y':
        print("Aborted")
        return

    update_version(args.version)

    if not args.no_tag:
        create_git_tag(args.version)

if __name__ == "__main__":
    main()
