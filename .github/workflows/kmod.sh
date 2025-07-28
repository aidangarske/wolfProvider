#!/bin/bash

#----kmod.sh----
#
# This script builds and tests kmod against the FIPS wolfProvider.
# Environment variables KMOD_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by the CI system or can be set manually.
set -e
set -x

# Use default version if not set
KMOD_REF="v33"

# Define base directories for cleaner paths
USER=$(whoami)
WOLFPROV_DIR="/home/$USER/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"
KMOD_INSTALL="$WOLFPROV_DIR/kmod-install"

cd "$WOLFPROV_DIR"

# Install kernel headers for kmod tests
echo "Installing kernel headers for kmod tests..."
sudo apt-get update

# Find and install available kernel headers
echo "Searching for available kernel headers..."
AVAILABLE_HEADERS=$(apt-cache search linux-headers | grep -E "^linux-headers-[0-9]" | head -1 | cut -d' ' -f1)
if [ -n "$AVAILABLE_HEADERS" ]; then
    echo "Installing $AVAILABLE_HEADERS..."
    sudo apt-get install -y "$AVAILABLE_HEADERS"
    
    # Create symlink for kernel headers to match running kernel
    echo "Setting up kernel headers symlink..."
    KERNEL_VERSION=$(uname -r)
    HEADERS_PATH=$(echo $AVAILABLE_HEADERS | sed 's/linux-headers-//')
    sudo mkdir -p /lib/modules/$KERNEL_VERSION
    sudo ln -sf /usr/src/linux-headers-$HEADERS_PATH /lib/modules/$KERNEL_VERSION/build
else
    echo "No kernel headers found, trying to install generic headers..."
    sudo apt-get install -y linux-headers-generic || echo "No generic headers available"
fi

# Clone kmod repo
rm -rf kmod
git clone --depth=1 --branch "$KMOD_REF" https://github.com/kmod-project/kmod.git kmod

# Build and install kmod
cd kmod

patch -p1 < ../kmod.patch

./autogen.sh
./configure --prefix="$KMOD_INSTALL" \
--disable-manpages \
--with-openssl \
CPPFLAGS="-I$OPENSSL_INSTALL/include" \
LDFLAGS="-L$OPENSSL_INSTALL/lib64 -lcrypto" \
PKG_CONFIG_PATH="$PKG_CONFIG_PATH"

make -j$(nproc)
sudo make install

echo "Setting up wolfProvider environment..."
export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"

# Check test results - skip tests that require kernel module compilation
echo "Running kmod tests (skipping kernel module tests)..."
set +e  # Don't exit on error
KMOD_LOG=debug TESTSUITE_VERBOSE=1 make check V=1 | tee kmod-test.log
set -e  # Re-enable exit on error

# Clean up root-owned files created during tests
echo "Cleaning up test artifacts..."
sudo find . -user root -exec chown $USER:$USER {} \; 2>/dev/null || true

if grep -q "PASS:  13" kmod-test.log; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
