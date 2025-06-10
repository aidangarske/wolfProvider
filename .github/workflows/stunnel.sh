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

# Create test directories
mkdir -p "$WOLFPROV_DIR/logs"
mkdir -p "$WOLFPROV_DIR/certs"

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
export STUNNEL_LOG="$WOLFPROV_DIR/logs/stunnel.log"
export STUNNEL_CERT_DIR="$WOLFPROV_DIR/certs"

# Build stunnel
cd stunnel
autoreconf -ivf
./configure --with-ssl="${OPENSSL_INSTALL}" \
            --with-threads=pthread \
            --disable-systemd \
            --disable-libwrap \
            --enable-fips

make -j$(nproc)

# Verify stunnel with wolfProvider
echo "Checking stunnel library dependencies:"
ldd src/stunnel | grep -E '(libssl|libcrypto)'
echo "Checking stunnel version and FIPS status:"
./src/stunnel -version

# Run tests with FIPS mode enabled
export STUNNEL_FIPS=1
export STUNNEL_DEBUG=7
make check TEST_VERBOSE=1

# Check test results
if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
    exit 0
else
  echo "Workflow failed"
    # Print debug information
    echo "=== stunnel.log ==="
    cat "$STUNNEL_LOG" || true
    echo "=== Test Logs ==="
    cat tests/*.log || true
  exit 1
fi
