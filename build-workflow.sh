#!/bin/bash

#----build-workflow.sh----
#
# This script builds and installs wolfProvider packages, then runs OpenLDAP tests
set -e
set -x

echo "=== Building wolfProvider Debian packages ==="

# Install build dependencies
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    devscripts \
    debhelper \
    dh-autoreconf \
    libtool \
    pkg-config \
    git \
    wget \
    curl \
    ca-certificates \
    openssl \
    dpkg-dev \
    lintian \
    fakeroot \
    dh-exec \
    equivs \
    expect \
    xxd

# Ensure the working directory is safe
git config --global --add safe.directory "$PWD"

# Fetch tags (for Debian versioning)
git fetch --tags --force --prune

git stash

# Install wolfSSL Debian packages from repo tarball
mkdir -p "/tmp/wolfssl-pkg"
chmod +x debian/install-wolfssl.sh
./debian/install-wolfssl.sh \
    .github/packages/debian-wolfssl.tar.gz \
    "/tmp/wolfssl-pkg"

# Stage wolfSSL debs into artifacts directory
mkdir -p "/tmp/wolfprov-packages"
find /tmp/wolfssl-pkg -name "*wolfssl*" -type f -name "*.deb" -exec cp {} /tmp/wolfprov-packages/ \;

# Build Debian packages (wolfProvider + OpenSSL)
yes Y | ./scripts/build-wolfprovider.sh --debian

# Collect package artifacts
mv ../*.deb /tmp/wolfprov-packages/ 2>/dev/null || true

echo "=== Installing packages ==="

# Install wolfSSL first
wolfssl_debs=$(ls -1 /tmp/wolfprov-packages/*wolfssl*.deb 2>/dev/null || true)
if [ -n "$wolfssl_debs" ]; then
  sudo apt install -y $wolfssl_debs
fi

# Install OpenSSL packages in dependency order
libssl3_debs=$(ls -1 /tmp/wolfprov-packages/libssl3_[0-9]*.deb 2>/dev/null || true)
openssl_debs=$(ls -1 /tmp/wolfprov-packages/openssl_[0-9]*.deb 2>/dev/null || true)
libssl_dev_debs=$(ls -1 /tmp/wolfprov-packages/libssl-dev_[0-9]*.deb 2>/dev/null || true)

if [ -n "$libssl3_debs" ]; then
  sudo apt install -y $libssl3_debs
fi
if [ -n "$openssl_debs" ]; then
  sudo apt install -y $openssl_debs
fi
if [ -n "$libssl_dev_debs" ]; then
  sudo apt install -y $libssl_dev_debs
fi

# Install wolfProvider main package
wolfprov_main=$(ls -1 /tmp/wolfprov-packages/libwolfprov_[0-9]*.deb 2>/dev/null | head -n1 || true)
if [ -z "$wolfprov_main" ]; then
  echo "ERROR: libwolfprov main package not found"
  exit 1
fi
sudo apt install -y "$wolfprov_main"

git stash pop
