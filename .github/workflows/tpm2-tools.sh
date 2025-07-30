#!/bin/bash

#----tpm2-tools.sh----
#
# This script runs the tpm2-tools tests against the FIPS wolfProvider.
# Environment variables TPM2_TOOLS_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
TPM2_TOOLS_REF="5.7"

# Define base directories for cleaner paths
USER=$(whoami)
WOLFPROV_DIR="/home/$USER/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Install system dependencies for tpm2-abrmd and tpm_server
echo "Installing system dependencies..."
sudo apt update
sudo apt install -y \
    libglib2.0-dev \
    libdbus-1-dev \
    libgirepository1.0-dev \
    libsystemd-dev \
    dbus \
    dbus-x11 \
    pkg-config \
    wget \
    build-essential

# Build tpm2-abrmd
echo "Building tpm2-abrmd..."
rm -rf tpm2-abrmd
git clone --depth=1 https://github.com/tpm2-software/tpm2-abrmd.git
cd tpm2-abrmd
./bootstrap
./configure --prefix="$WOLFPROV_DIR/tpm2-abrmd-install" \
  --with-dbuspolicydir=/etc/dbus-1/system.d \
  --with-udevrulesdir=/usr/lib/udev/rules.d \
  --with-systemdsystemunitdir=/usr/lib/systemd/system \
  --libdir="$WOLFPROV_DIR/tpm2-abrmd-install/lib64"
make -j$(nproc)
make install
cd "$WOLFPROV_DIR"

# Build IBM TPM simulator (tpm_server)
echo "Building IBM TPM simulator..."
mkdir -p ibmtpm
cd ibmtpm
wget https://sourceforge.net/projects/ibmswtpm2/files/latest/download -O ibmtpm.tar.gz
tar -xzf ibmtpm.tar.gz
cd src
make -j$(nproc)
# Copy tpm_server to a location in PATH
sudo cp tpm_server /usr/local/bin/
cd "$WOLFPROV_DIR"

# Clone tpm2-tools repo
rm -rf tpm2-tools
git clone --depth=1 --branch="${TPM2_TOOLS_REF}" https://github.com/tpm2-software/tpm2-tools.git

cd tpm2-tools

# Add tpm2-abrmd to PATH
export PATH="$WOLFPROV_DIR/tpm2-abrmd-install/bin:$PATH"

# Configure tpm2-tools to use wolfProvider and enable tests
./bootstrap
./configure \
  --prefix="$WOLFPROV_DIR/tpm2-tools-install" \
  --with-openssl="${OPENSSL_INSTALL}" \
  --enable-unit \
  --disable-fapi \
  PATH="$PATH"

# Build tpm2-tools
make -j$(nproc)

# Setup wolfProvider environment
echo "Setting up environment..."
# export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"

# Set up test environment to use tabrmd properly
# The key is to let the test framework handle the TCTI configuration
# instead of trying to override it with a hardcoded port
export TPM2_ABRMD="$WOLFPROV_DIR/tpm2-abrmd-install/bin/tpm2-abrmd"
export TPM2_SIM="tpm_server"

# Start D-Bus daemon for tpm2-abrmd
echo "Starting D-Bus daemon..."
sudo mkdir -p /var/run/dbus
sudo dbus-daemon --system --fork
sleep 2

# Verify D-Bus is running
if ! pgrep dbus-daemon > /dev/null; then
    echo "ERROR: D-Bus daemon failed to start"
    exit 1
fi
echo "D-Bus daemon is running"

# Run the tests
echo "Running tpm2-tools tests..."
make check

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
