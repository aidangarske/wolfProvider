#!/bin/bash

#----sssd.sh----
#
# This script runs the SSSD tests against the FIPS wolfProvider.
# Environment variables SSSD_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by the CI system or can be set manually.
set -e
set -x

# Use default version if not set
SSSD_REF="${SSSD_REF:-2.9.1}"
WOLFSSL_REF="${WOLFSSL_REF:-v5.8.0-stable}"
OPENSSL_REF="${OPENSSL_REF:-openssl-3.5.0}"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/user/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

cd "$WOLFPROV_DIR"

echo "[*] Cloning SSSD..."
rm -rf sssd
git clone --branch=${SSSD_REF} https://github.com/SSSD/sssd.git
cd sssd
git checkout $SSSD_REF

echo "[*] Building SSSD with wolfProvider..."
# Configure and build SSSD with wolfProvider
autoreconf -ivf
./configure --without-samba --disable-cifs-idmap-plugin \
    --without-nfsv4-idmapd-plugin --with-oidc-child=no
make -j

# Source environment setup if available
if [ -f "scripts/env-setup" ]; then
    echo "Setting up environment..."
    source scripts/env-setup
fi

# Set environment variables for FIPS testing
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64:${LD_LIBRARY_PATH}"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"
export PATH="${OPENSSL_INSTALL}/bin:${PATH}"

echo "Checking OpenSSL providers:"
$OPENSSL_INSTALL/bin/openssl list -providers | tee provider-list.log
grep -q libwolfprov provider-list.log || (echo "ERROR: libwolfprov not found in OpenSSL providers" && exit 1)

# Run tests and save result
make check 2>&1 | tee sssd-test.log
TEST_RESULT=${PIPESTATUS[0]}

echo "[*] Test completed with exit code: $TEST_RESULT"
echo "[*] All done."
echo "Workflow completed successfully"
