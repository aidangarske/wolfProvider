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

# Detect current user and set paths accordingly
CURRENT_USER=$(whoami)
WOLFPROV_DIR="/home/${CURRENT_USER}/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"
rm -rf stunnel
git clone --depth=1 --branch="${STUNNEL_REF}" https://github.com/mtrojnar/stunnel.git

# Only rebuild OpenSSL if specified or if not already built
cd openssl-source
# Define OpenSSL installation paths
OPENSSL_PREFIX="$WOLFPROV_DIR/openssl-install"
OPENSSL_DIR="${OPENSSL_PREFIX}/ssl"
OPENSSL_LIB="${OPENSSL_PREFIX}/lib64"

# Configure OpenSSL with modular paths
./config \
    --prefix="${OPENSSL_PREFIX}" \
    --openssldir="${OPENSSL_DIR}" \
    -Wl,-rpath,"${OPENSSL_LIB}"
make
make install
cd ..

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
"${OPENSSL_INSTALL}/bin/openssl" list -providers

# Build stunnel
cd stunnel

patch -p1 < ../stunnel-tests.patch

autoreconf -ivf

# Configure stunnel with proper LDFLAGS and rpath to link against our custom OpenSSL
LDFLAGS="-L${OPENSSL_INSTALL}/lib64 -Wl,-rpath,${OPENSSL_INSTALL}/lib64" \
PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig" \
./configure --with-ssl="${OPENSSL_INSTALL}"

make -j$(nproc)

# Verify stunnel with wolfProvider
echo "Checking stunnel library dependencies:"
ldd src/stunnel | grep -E '(libssl|libcrypto)'
echo "Checking stunnel version and FIPS status:"
./src/stunnel -version

# Run tests with FIPS mode enabled
export STUNNEL_FIPS=1
export STUNNEL_DEBUG=7

# Generate certificates first
cd tests/certs
./maketestcert.sh
cd ..

# Override the Makefile's --libs argument to include wolfSSL library path
for v in $(seq 20 -1 7); do 
    command -v python3.$v && python3.$v ./maketest.py --debug=10 --libs="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64:${OPENSSL_INSTALL}/lib" && break
done

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
