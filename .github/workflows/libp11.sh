#!/bin/bash

#----libp11.sh----
#
# This script runs the libp11 tests against the FIPS wolfProvider.
# Environment variables LIBP11_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
LIBP11_REF="0.4.12"

# Define base directories for cleaner paths
USER=$(whoami)
WOLFPROV_DIR="/home/$USER/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Clone libp11 repo
rm -rf libp11
git clone --depth=1 --branch="${LIBP11_REF}" https://github.com/OpenSC/libp11.git

cd libp11

# Apply patch to fix missing includes
patch -p1 < ../libp11-fix-includes.patch

# Bootstrap the build system
./bootstrap

# Configure with custom OpenSSL and wolfProvider
OPENSSL_CFLAGS="-I${OPENSSL_INSTALL}/include" \
OPENSSL_LIBS="-L${OPENSSL_INSTALL}/lib64 -lcrypto" \
./configure \
    --prefix="${WOLFPROV_DIR}/libp11-install" \
    --with-enginesdir="${WOLFPROV_DIR}/libp11-install/lib/engines-3" \
    --with-modulesdir="${WOLFPROV_DIR}/libp11-install/lib/ossl-modules" \
    CFLAGS="-Wno-error" \
    LDFLAGS="-L${OPENSSL_INSTALL}/lib64" \
    CPPFLAGS="-I${OPENSSL_INSTALL}/include"

# Build libp11
make -j$(nproc)

# Install libp11
make install

# Setup wolfProvider environment
echo "Setting up environment..."
export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"

# Set up SoftHSM for testing
echo "Setting up SoftHSM for testing..."
export SOFTHSM2_CONF="${WOLFPROV_DIR}/softhsm2.conf"
mkdir -p "${WOLFPROV_DIR}/softhsm2-tokens"

# Create SoftHSM configuration
cat > "${SOFTHSM2_CONF}" << EOF
directories.tokendir = ${WOLFPROV_DIR}/softhsm2-tokens
objectstore.backend = file
log.level = DEBUG
EOF

# Initialize SoftHSM token
softhsm2-util --init-token --slot 0 --label "test-token" --pin 1234 --so-pin 1234

# Run libp11 tests
echo "Running libp11 tests..."
make check

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi 