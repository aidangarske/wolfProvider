#!/bin/bash

#----libssh2.sh----
#
# This script runs the libssh2 tests against the FIPS wolfProvider.
# Environment variables LIBSSH2_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
LIBSSH2_REF="libssh2-1.10.0"

# Define base directories for cleaner paths
USER=$(whoami)
WOLFPROV_DIR="/home/${USER}/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Set up locale to fix mansyntax.sh test
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# Clone libssh2 repo
rm -rf libssh2
git clone --depth=1 --branch="${LIBSSH2_REF}" https://github.com/libssh2/libssh2.git

# Build libssh2
cd libssh2

echo "Setting up environment..."
export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"

# Build libssh2
autoreconf -fi
./configure --with-crypto=openssl --with-libssl-prefix="${OPENSSL_INSTALL}"
make -j$(nproc)

# Source environment setup script for proper configuration
echo "Setting up environment..."
export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"

# Run the tests
DEBUG=1 make check

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
