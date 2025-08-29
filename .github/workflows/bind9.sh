#!/bin/bash

#----bind9.sh----
#
# This script runs the bind9 tests against the FIPS wolfProvider.
# Environment variables BIND_REF, WOLFSSL_REF, and OPENSSL_REF
# can be set to override defaults.
set -e
set -x

# Use stable versions instead of specific commits
BIND_REF="v9.18.28"

# Define base directories for cleaner paths
USER=$(whoami)
WOLFPROV_DIR="/home/$USER/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Install bind9 test dependencies
echo "Installing bind9 test dependencies..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt install -y build-essential automake libtool gnutls-bin \
    pkg-config make libidn2-dev libuv1-dev libnghttp2-dev libcap-dev \
    libjemalloc-dev zlib1g-dev libxml2-dev libjson-c-dev libcmocka-dev \
    python3-pytest python3-dnspython python3-hypothesis
sudo PERL_MM_USE_DEFAULT=1 cpan -i Net::DNS

# Clone bind9 repo
echo "Cloning bind9..."
rm -rf bind9
git clone --depth=1 --branch="${BIND_REF}" https://github.com/isc-projects/bind9.git

# Apply wolfProvider patch to bind9
echo "Applying wolfProvider patch to bind9..."
cd bind9
patch -p1 < "$WOLFPROV_DIR/bind9.patch"

# Setup wolfProvider environment
echo "Setting up environment..."
export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"

# Build bind9 with wolfProvider
echo "Building bind9 with wolfProvider..."
autoreconf -ivf
./configure
make clean
make -j$(nproc)

# Setup network interfaces for tests
echo "Setting up network interfaces..."
sudo ./bin/tests/system/ifconfig.sh up

# Run the tests
echo "Running bind9 tests..."
make -j$(nproc) check

if [ $? -eq 0 ]; then
    echo "bind9 tests completed successfully"
else
    echo "bind9 tests failed"
    exit 1
fi
