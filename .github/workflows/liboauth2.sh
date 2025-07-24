#!/bin/bash

#----liboauth2.sh----
#
# This script runs the liboauth2 tests against the FIPS wolfProvider.
# Environment variables LIBOAUTH2_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
LIBOAUTH2_REF="v1.4.5.4"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/user/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Clone liboauth2 repo
rm -rf liboauth2
git clone --depth=1 --branch="${LIBOAUTH2_REF}" https://github.com/OpenIDC/liboauth2.git

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"

# Build liboauth2
cd liboauth2

# Apply wolfProvider non fips patch if it exists
patch -p1 < "${WOLFPROV_DIR}/liboauth2-fips.patch"

# Configure and build
autoreconf -fiv
./configure --enable-wolfprov-fips
make -j

# Run tests
make check 2>&1 | tee liboauth2-test.log
TEST_RESULT=$?

if [ $TEST_RESULT -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed with exit code $TEST_RESULT"
  exit 1
fi
