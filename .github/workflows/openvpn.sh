#!/bin/bash

#----openvpn.sh----
#
# This script runs the OpenVPN tests against the FIPS wolfProvider.
# Environment variables OPENVPN_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
# TODO: Add FORCE_FAIL neg testing
set -e
set -x

# Use stable version instead of specific commit
OPENVPN_REF="v2.6.7"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/user/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Clone OpenVPN repo
rm -rf openvpn
git clone --depth=1 --branch="${OPENVPN_REF}" https://github.com/OpenVPN/openvpn.git

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
"${OPENSSL_INSTALL}/bin/openssl" list -providers

# Build OpenVPN
cd openvpn
autoreconf -ivf
./configure
make -j

# Run tests
make check

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
