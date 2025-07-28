#!/bin/bash

#----systemd.sh----
# This script runs the systemd tests against the FIPS wolfProvider.
# Environment variables: SYSTEMD_REF, WOLFSSL_REF, OPENSSL_REF, FORCE_FAIL
set -e
set -x

# Set default refs if not provided
SYSTEMD_REF="v254"

# Define base directories for cleaner paths
USER=$(whoami)
WOLFPROV_DIR="/home/${USER}/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

cd "$WOLFPROV_DIR"

# Clone systemd
rm -rf systemd
git clone --depth=1 --branch="${SYSTEMD_REF}" https://github.com/systemd/systemd.git systemd

cd systemd

# Set up wolfProvider environment
echo "Setting up wolfProvider environment..."
export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"

# Build systemd
meson setup -Dnobody-group=nogroup build
ninja -C build

# Run systemd tests
set +e
# The following test cases link directly to libcrypto.
TEST_CASES="fuzz-dns-packet fuzz-etc-hosts fuzz-resource-record \
            resolvectl systemd-resolved test-cryptolib \
            test-dns-packet test-dnssec test-resolve-tables \
            test-resolved-etc-hosts test-resolved-packet \
            test-resolved-stream"

meson test -C build $TEST_CASES

if [ $? -eq 0 ]; then
    echo "systemd workflow completed successfully"
else
    echo "systemd workflow failed"
    exit 1
fi
