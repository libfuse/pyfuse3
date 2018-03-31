#!/bin/sh

set -e

pip install pytest cython sphinx
cython --version
