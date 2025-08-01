#!/bin/bash

#----libcryptsetup.sh----
#
# This script runs the cryptsetup tests against the FIPS wolfProvider.
# Environment variables CRYPTSETUP_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
CRYPTSETUP_REF="v2.6.1"

# Define base directories for cleaner paths
USER=$(whoami)
WOLFPROV_DIR="/home/$USER/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

cd "$WOLFPROV_DIR"

# Clone cryptsetup repo
rm -rf cryptsetup
git clone --depth=1 --branch="${CRYPTSETUP_REF}" https://github.com/mbroz/cryptsetup.git

cd cryptsetup

# Apply patch to disable PBKDF2
patch -p1 < "$WOLFPROV_DIR/libcryptsetup.patch"

# Build cryptsetup with custom OpenSSL
echo "Building cryptsetup..."
./autogen.sh
./configure --enable-static \
  --with-crypto_backend=openssl \
  --disable-ssh-token \
  CPPFLAGS="-I$OPENSSL_INSTALL/include" \
  LDFLAGS="-L$OPENSSL_INSTALL/lib64"
make -j$(nproc)

echo "Setting up environment..."
# export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"

# Run cryptsetup tests
echo "Running cryptsetup tests..."
make check

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
