#!/bin/sh

set -e

pip install pytest cython sphinx trio pytest-trio sphinxcontrib-asyncio
cython --version

pip install meson

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
