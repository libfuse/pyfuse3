#!/bin/bash

set -e

# Disable developer mode, so that build does not suddenly break if
# e.g. a newer compiler version results in new warning messages.
rm MANIFEST.in

python setup.py build_cython
python setup.py build_ext --inplace
python -m pytest test/

python setup.py build_sphinx
