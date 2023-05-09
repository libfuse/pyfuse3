#!/bin/sh

set -e

# We're pinning most packages to specific versions to prevent the CI from failing when
# testing eg merge requests because some of those packages have started emitting
# depreciation warnings or made backwards incompatible changes.
pip install \
    trio \
    pytest \
    pytest_trio \
    "sphinx<6.0" \
    sphinxcontrib-asyncio \
    Cython
