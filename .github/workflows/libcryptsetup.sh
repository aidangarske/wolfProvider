#!/bin/bash

#----libcryptsetup.sh----
#
# This script runs the cryptsetup tests against the FIPS wolfProvider.
# Environment variables CRYPTSETUP_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
CRYPTSETUP_REF="v2.6.1"

# Define base directories for cleaner paths
USER=$(whoami)
WOLFPROV_DIR="/home/$USER/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

cd "$WOLFPROV_DIR"

# Install system dependencies
sudo apt update
sudo apt install -y \
    build-essential \
    autoconf \
    libtool \
    pkg-config \
    uuid-dev \
    libdevmapper-dev \
    libpopt-dev \
    libjson-c-dev \
    libargon2-dev

# Clone cryptsetup repo
rm -rf cryptsetup
git clone --depth=1 --branch="${CRYPTSETUP_REF}" https://github.com/mbroz/cryptsetup.git

cd cryptsetup

# Setup wolfProvider environment BEFORE configuring
echo "Setting up environment..."
export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"

# Build cryptsetup with custom OpenSSL
echo "Building cryptsetup..."
./autogen.sh
./configure --enable-static \
  --with-crypto_backend=openssl
make -j$(nproc)

# Run cryptsetup tests
echo "Running cryptsetup tests..."
export WOLFPROV_FORCE_FAIL=1
make check

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
