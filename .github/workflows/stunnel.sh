#!/bin/bash

#----stunnel.sh----
#
# This script runs the stunnel tests against the FIPS wolfProvider.
# Environment variables STUNNEL_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
STUNNEL_REF="stunnel-5.67"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/aidangarske/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Clone stunnel repo
rm -rf stunnel
git clone --depth=1 --branch="${STUNNEL_REF}" https://github.com/mtrojnar/stunnel.git

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"

# Build stunnel
cd stunnel
autoreconf -ivf
./configure --with-ssl="${OPENSSL_INSTALL}"
make -j$(nproc)

# Verify stunnel with wolfProvider
ldd src/stunnel | grep -E '(libssl|libcrypto)'
./src/stunnel -version

# Run tests
make check

if [ $TEST_RESULT -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
