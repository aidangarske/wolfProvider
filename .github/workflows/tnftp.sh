#!/bin/bash

#----tnftp.sh----
#
# This script runs the tnftp tests against the FIPS wolfProvider.
# Environment variables TNFTP_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
TNFTP_REF="tnftp-20210827"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/user/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Download and extract tnftp
rm -rf tnftp
wget http://ftp.netbsd.org/pub/NetBSD/misc/tnftp/${TNFTP_REF}.tar.gz
tar xvf ${TNFTP_REF}.tar.gz
cd ${TNFTP_REF}

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"

# Configure with OpenSSL
./configure --with-openssl="$OPENSSL_INSTALL"

# Build tnftp
make -j

# Set up the environment for wolfProvider (equivalent to source scripts/env-setup)
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64:$LD_LIBRARY_PATH"

# Run tests and capture output
echo "Testing tnftp basic functionality..."

# Test help command
if ./src/tnftp -? 2>&1 | grep -q "usage:"; then
    echo "tnftp help command works"
else
    echo "tnftp help command failed"
    exit 1
fi

# Test that tnftp can start (even if it fails to connect)
echo "Testing tnftp connection attempt..."
if ! timeout 10 ./src/tnftp -n 192.0.2.1 2>&1 | head -10; then
    echo "tnftp connection attempt failed"
    exit 1
fi
echo "tnftp can attempt connections"

# Test SSL/TLS functionality
echo "Testing SSL/TLS connection..."
if ! timeout 15 ./src/tnftp -n https://httpbin.org/get 2>&1; then
    echo "SSL/TLS test failed"
    exit 1
fi
echo "SSL/TLS test completed"

echo "Workflow completed successfully"
