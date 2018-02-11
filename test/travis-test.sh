#!/bin/bash

set -e

python setup.py build_cython
python setup.py build_ext --inplace
python -m pytest test/

python setup.py build_sphinx
