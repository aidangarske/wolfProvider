#!/bin/bash

#----opensc.sh----
#
# This script runs the OpenSC tests against the FIPS wolfProvider.
# Environment variables OPENSC_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
OPENSC_REF="0.25.1"

# Define base directories for cleaner paths
USER=$(whoami)
WOLFPROV_DIR="/home/${USER}/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Clone OpenSC repo
rm -rf opensc
git clone --depth=1 --branch="${OPENSC_REF}" https://github.com/OpenSC/OpenSC.git opensc

cd opensc

patch -p1 < ../wolfprov-opensc.patch

# Bootstrap the build system
./bootstrap

# Configure with custom OpenSSL and wolfProvider
OPENSSL_CFLAGS="-I${OPENSSL_INSTALL}/include" \
OPENSSL_LIBS="-L${OPENSSL_INSTALL}/lib64 -lcrypto" \
./configure \
    --enable-openssl \
    --enable-pcsc \
    --disable-doc \
    --prefix="${WOLFPROV_DIR}/opensc-install" \
    --with-completiondir="${WOLFPROV_DIR}/opensc-install/share/completions" \
    CFLAGS="-Wno-error" \
    LDFLAGS="-L${OPENSSL_INSTALL}/lib64" \
    CPPFLAGS="-I${OPENSSL_INSTALL}/include"

# Build OpenSC
make -j$(nproc)

# Install OpenSC
make install

# Source environment setup script for proper wolfProvider configuration
echo "Setting up wolfProvider environment..."
# export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"

# Enable wolfProvider for OpenSC
make check

if [ $? -eq 0 ]; then
    echo "OpenSC PKCS#11 workflow completed successfully"
else
    echo "OpenSC PKCS#11 workflow failed"
    exit 1
fi 
