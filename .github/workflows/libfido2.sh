#!/bin/bash

#----libfido2.sh----
#
# This script runs the libfido2 tests against the FIPS wolfProvider.
# Environment variables LIBFIDO2_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by the CI system or can be set manually.
set -e
set -x

# Use default version if not set
LIBFIDO2_REF="1.15.0"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/user/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"
LIBFIDO2_INSTALL="$WOLFPROV_DIR/libfido2-install"

cd "$WOLFPROV_DIR"

# Clone libfido2 repo
rm -rf libfido2_repo
git clone --depth=1 --branch "$LIBFIDO2_REF" https://github.com/Yubico/libfido2.git libfido2_repo

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
"${OPENSSL_INSTALL}/bin/openssl" list -providers

# Build and install libfido2
cd libfido2_repo

patch -p1 < ../libfido2_repo.patch

rm -rf build
mkdir -p build
cd build
cmake -DCMAKE_INSTALL_PREFIX="$LIBFIDO2_INSTALL" -DHAVE_FIPS=ON ..
make -j$(nproc)
make install

# Run tests, excluding regress_dev which requires hardware/fails in CI
ctest --exclude-regex "regress_dev" 2>&1 | tee libfido2-test.log

# Check test results
if grep -q "100% tests passed" libfido2-test.log; then
  echo "Workflow completed successfully"
  exit 0
else
  echo "Workflow failed: not all tests passed"
  exit 1
fi
