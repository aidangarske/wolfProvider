#!/bin/bash

#----ipmitool.sh----
#
# This script runs the ipmitool tests against the FIPS wolfProvider.
# Environment variables IPMITOOL_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
# TODO: Add FORCE_FAIL neg testing
set -e
set -x

# Use stable version instead of specific commit
IPMITOOL_REF="IPMITOOL_1_8_19"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/aidangarske/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Clone ipmitool repo
rm -rf ipmitool
git clone --depth=1 --branch="${IPMITOOL_REF}" https://github.com/ipmitool/ipmitool.git
cd ipmitool

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"

# Build ipmitool
autoreconf -ivf
./configure
make -j$(nproc)

# Verify ipmitool was built and linked correctly with OpenSSL
ldd src/ipmitool | grep -E '(libssl|libcrypto)'
ldd src/ipmievd | grep -E '(libssl|libcrypto)'

# Run a simple command to verify functionality
./src/ipmitool -V

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
