#!/bin/bash

#----openvpn.sh----
#
# This script runs the OpenVPN tests against the FIPS wolfProvider.
# Environment variables OPENVPN_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
OPENVPN_REF="v2.6.7"

# Define base directories for cleaner paths
USER=$(whoami)
WOLFPROV_DIR="/home/${USER}/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Clone OpenVPN repo
rm -rf openvpn
git clone --depth=1 --branch="${OPENVPN_REF}" https://github.com/OpenVPN/openvpn.git

# Build OpenVPN
cd openvpn
autoreconf -ivf
./configure
make -j

# Source environment setup script for proper configuration
echo "Setting up environment..."
export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"

# Run tests
make check

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
