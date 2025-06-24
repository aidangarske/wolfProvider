#!/bin/bash

#----sssd.sh----
#
# This script runs the SSSD tests against the FIPS wolfProvider.
# Environment variables SSSD_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

SSSD_REF="2.9.1"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/user/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"

# Clone SSSD
rm -rf sssd
git clone --depth=1 --branch="${SSSD_REF}" https://github.com/SSSD/sssd.git

# Build and test SSSD with wolfProvider
cd sssd
autoreconf -ivf
./configure --without-samba \
            --disable-cifs-idmap-plugin \
            --without-nfsv4-idmapd-plugin \
            --with-oidc-child=no
make -j$(nproc)

# Run tests
make check VERBOSE=1

if [ $TEST_RESULT -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
