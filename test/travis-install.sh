#!/bin/sh

set -e

# We're pinning most packages to specific versions to prevent the CI from failing when
# testing eg merge requests because some of those packages have started emitting
# depreciation warnings or made backwards incompatible changes.
pip install \
    cython \
    sphinx \
    "trio == 0.15" \
    "pytest >= 4.6.5, < 5.0.0" \
    "pytest_trio == 0.6.0" \
    sphinxcontrib-asyncio

cython --version

pip install meson ninja

ninja --version
meson --version

# Install fuse
wget https://github.com/libfuse/libfuse/archive/master.zip
unzip master.zip
cd libfuse-master
mkdir build
cd build
meson ..
ninja
sudo ninja install
test -e /usr/local/lib/pkgconfig || sudo mkdir /usr/local/lib/pkgconfig
sudo mv /usr/local/lib/*/pkgconfig/* /usr/local/lib/pkgconfig/
ls -d1 /usr/local/lib/*-linux-gnu | sudo tee /etc/ld.so.conf.d/usrlocal.conf
sudo ldconfig
