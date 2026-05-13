#!/usr/bin/env python3
"""Automate the mechanical steps of a pyfuse3 release.

Reads the version of the new release from the topmost version heading in
`Changes.rst`. Then, in order: optionally rotates signify keys for a new
minor/major release, commits and tags the release, builds the docs and sdist,
signs the tarball, and writes a ready-to-send announcement to
`dist/announcement-<ver>.txt`.
"""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHANGES = ROOT / 'Changes.rst'
SIGNIFY_DIR = ROOT / 'signify'

VERSION_HEADING_RE = re.compile(
    r'^(?:pyfuse|Release)\s+(\d+\.\d+\.\d+)\s+\([0-9]{4}-[0-9]{2}-[0-9]{2}\)\s*$'
)

ANNOUNCEMENT_TEMPLATE = """\
Dear all,

I'm happy to announce a new release of pyfuse3, version {new_ver}.

pyfuse3 is a set of Python 3 bindings for libfuse 3. It provides an
asynchronous API compatible with Trio and asyncio, and enables you to easily
write a full-featured Linux filesystem in Python.

From the changelog:

{changelog}

The following people have contributed code to this release:

{contributors}

As usual, the newest release can be downloaded from PyPi at
https://pypi.python.org/pypi/pyfuse3/.

Please report any bugs on the issue tracker at
https://github.com/libfuse/pyfuse3/issues. For discussion and questions, please
use the general FUSE mailing list (i.e., this list) or the GitHub discussion
forum at https://github.com/libfuse/pyfuse3/discussions.
"""


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    """Run *cmd*, echoing it first. Raises on non-zero exit."""
    print('+', ' '.join(cmd), flush=True)
    return subprocess.run(cmd, check=True, text=True)


def capture(cmd: list[str]) -> str:
    print('+', ' '.join(cmd), flush=True)
    return subprocess.run(cmd, check=True, text=True, capture_output=True).stdout


def parse_changes() -> tuple[str, str]:
    """Return *(new_ver, changelog_body)* parsed from `Changes.rst`."""
    lines = CHANGES.read_text().splitlines()
    new_ver: str | None = None
    body_start: int | None = None
    body_end: int = len(lines)
    for i, line in enumerate(lines):
        # An RST section heading is two consecutive lines: title, then an
        # underline made of the same character.
        if i + 1 >= len(lines):
            continue
        underline = lines[i + 1]
        if not underline or set(underline) - {'=', '-'} or len(underline) < len(line):
            continue
        m = VERSION_HEADING_RE.match(line)
        if not m:
            continue
        if new_ver is None:
            new_ver = m.group(1)
            body_start = i + 2
        else:
            body_end = i
            break
    if new_ver is None or body_start is None:
        sys.exit(
            "error: no 'pyfuse X.Y.Z (YYYY-MM-DD)' heading found in Changes.rst — "
            'edit the "Unreleased Changes" section to a real release heading first.'
        )
    body = '\n'.join(lines[body_start:body_end]).rstrip()
    return new_ver, body


def signing_keys_dir() -> Path:
    val = os.environ.get('PYFUSE_SIGNING_KEYS_DIR')
    if not val:
        sys.exit('error: $PYFUSE_SIGNING_KEYS_DIR is not set.')
    p = Path(val)
    if not p.is_dir():
        sys.exit(f'error: $PYFUSE_SIGNING_KEYS_DIR={val!r} is not a directory.')
    return p


def rotate_keys(major_rev: str, prev_major_rev: str, keys_dir: Path) -> None:
    print(f'Rotating signify keys for new major revision {major_rev} (was {prev_major_rev}).')
    next_pub = SIGNIFY_DIR / 'pyfuse-next.pub'
    next_sec = keys_dir / 'pyfuse-next.sec'
    new_pub = SIGNIFY_DIR / f'pyfuse-{major_rev}.pub'
    new_sec = keys_dir / f'pyfuse-{major_rev}.sec'
    if not next_pub.exists():
        sys.exit(f'error: expected {next_pub} to exist for key rotation.')
    if not next_sec.exists():
        sys.exit(f'error: expected {next_sec} to exist for key rotation.')
    next_pub.rename(new_pub)
    next_sec.rename(new_sec)
    run(
        [
            'signify',
            '-G',
            '-n',
            '-p',
            str(next_pub),
            '-s',
            str(next_sec),
        ]
    )
    prev_pub = SIGNIFY_DIR / f'pyfuse-{prev_major_rev}.pub'
    if prev_pub.exists():
        print(f'Removing obsolete public key {prev_pub}.')
        prev_pub.unlink()


def contributor_list(prev_tag: str, new_tag: str) -> str:
    raw = capture(['git', 'log', '--pretty=format:%an <%aE>', f'{prev_tag}..{new_tag}'])
    seen = sorted({ln.strip() for ln in raw.splitlines() if ln.strip()})
    return '\n'.join(seen) if seen else '(none)'


def main() -> None:
    os.chdir(ROOT)
    for tool in ('git', 'signify', 'uv'):
        if shutil.which(tool) is None:
            sys.exit(f'error: required tool not found in $PATH: {tool}')

    new_ver, changelog = parse_changes()
    major_rev = new_ver.rsplit('.', 1)[0]
    new_tag = f'v{new_ver}'
    print(f'Releasing pyfuse3 {new_ver} (major revision {major_rev}).')

    prev_tag = capture(['git', 'describe', '--tags', '--abbrev=0', '--match', 'v*']).strip()
    prev_ver = prev_tag.removeprefix('v')
    prev_major_rev = prev_ver.rsplit('.', 1)[0]

    if major_rev != prev_major_rev:
        rotate_keys(major_rev, prev_major_rev, signing_keys_dir())
    else:
        print(f'Bugfix release on {major_rev}; no key rotation needed.')

    run(['git', 'commit', '--all', '-m', f'Released {new_ver}'])
    run(['git', 'tag', new_tag])

    run(['uv', 'sync', '--locked'])
    run(['uv', 'run', 'sphinx-build', '-W', '-b', 'html', 'rst', 'doc/html'])
    run(['uv', 'build', '--sdist'])

    tarball = ROOT / 'dist' / f'pyfuse3-{new_ver}.tar.gz'
    if not tarball.exists():
        sys.exit(f'error: expected {tarball} to exist after `uv build`.')
    sec_key = signing_keys_dir() / f'pyfuse-{major_rev}.sec'
    run(['signify', '-S', '-s', str(sec_key), '-m', str(tarball)])

    announcement = ANNOUNCEMENT_TEMPLATE.format(
        new_ver=new_ver,
        changelog=changelog,
        contributors=contributor_list(prev_tag, new_tag),
    )

    print()
    print(f'Release {new_ver} prepared. Remaining manual steps:')
    print()
    print('--- announcement ---')
    print(announcement)


if __name__ == '__main__':
    main()
