#!/bin/bash

#----cjose.sh----
#
# This script runs the cjose tests against the FIPS wolfProvider.
# Environment variables CJOSE_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
CJOSE_REF="v0.6.2.1"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/user/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/usr"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Clone cjose repo
rm -rf cjose
git clone --depth=1 --branch="${CJOSE_REF}" https://github.com/OpenIDC/cjose.git

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"

# Build cjose
cd cjose

# Configure with OpenSSL and disable deprecated declaration warnings
./configure CFLAGS="-Wno-error=deprecated-declarations" \
            --with-openssl="${OPENSSL_INSTALL}"

# Build cjose  
make -j

# Source environment setup script for proper configuration
echo "Setting up environment..."
export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"

# Run tests
make test

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
