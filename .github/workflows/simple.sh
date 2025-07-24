#!/bin/bash

#----simple.sh----
#
# This script runs the simple tests against the FIPS wolfProvider.
# Environment variables BUILD_REF, OPENSSL_REF, and FORCE_FAIL
# are set by Jenkins.
set -e
set -x

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/aidangarske/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"
export GIT_DISCOVERY_ACROSS_FILESYSTEM=1

# Run the simple tests
./scripts/cmd_test/do-cmd-tests.sh

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
