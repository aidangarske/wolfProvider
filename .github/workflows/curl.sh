#!/bin/bash

#----curl.sh----
#
# This script runs the curl tests against the FIPS wolfProvider.
# Environment variables CURL_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
CURL_REF="curl-8_4_0"

# Define base directories for cleaner paths
USER=$(whoami)
WOLFPROV_DIR="/home/$USER/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Clone curl repo
rm -rf curl
git clone --depth=1 --branch="${CURL_REF}" https://github.com/curl/curl.git

# Disable test 1560 which requires IDN support (libidn2) that may not be available in all environments
cd curl/tests/data
if ! grep -q "^1560$" DISABLED; then
    echo "# test 1560 requires IDN support (libidn2) which may not be available in all environments" >> DISABLED
    echo "1560" >> DISABLED
fi
cd "$WOLFPROV_DIR"

# Setup wolfProvider environment
echo "Setting up environment..."
export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"

# Build curl
cd curl
autoreconf -ivf
./configure --with-openssl
make -j$(nproc)

# Run the tests
make test-ci

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
