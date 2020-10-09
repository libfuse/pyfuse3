#!/bin/sh

set -e

# We're pinning most packages to specific versions to prevent the CI from failing when
# testing eg merge requests because some of those packages have started emitting
# depreciation warnings or made backwards incompatible changes.
pip install \
    "trio == 0.15" \
    "pytest >= 4.6.5, < 5.0.0" \
    "pytest_trio == 0.6.0" \
    sphinxcontrib-asyncio
