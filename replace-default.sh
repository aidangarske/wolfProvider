#!/bin/bash
#
# Copyright (C) 2006-2024 wolfSSL Inc.
#
# This file is part of wolfProvider.
#
# wolfProvider is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# wolfProvider is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with wolfProvider. If not, see <http://www.gnu.org/licenses/>.
#
# This script builds and installs wolfSSL/OpenSSL/wolfProvider packages to 
# replace the default provider to always use wolfProvider.

set -e
set -x

# Parse command line arguments
FIPS_MODE=false
FIPS_DEBS_PATH=""
WOLFSSL_TAG="v5.8.2-stable"
DEBS_REPO="https://github.com/wolfSSL/wolfProvider.git"
DEBS_BRANCH="debs"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --fips                  Enable FIPS mode (downloads pre-built FIPS wolfSSL debs)
    --fips-debs-path PATH   Path to directory containing FIPS wolfSSL .deb files
                            (optional - if not specified, debs will be downloaded from debs branch)
    --wolfssl-tag TAG       WolfSSL tag to build from source (default: v5.8.2-stable)
                            (ignored when --fips is specified)
    -h, --help              Show this help message

Examples:
    # Build non-FIPS version from source
    $0
    
    # Build FIPS version using downloaded debs (automatic)
    $0 --fips
    
    # Build FIPS version using local debs
    $0 --fips --fips-debs-path /path/to/wolfssl-fips-debs
    
    # Build non-FIPS with specific wolfSSL tag
    $0 --wolfssl-tag v5.7.4-stable
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --fips)
            FIPS_MODE=true
            shift
            ;;
        --fips-debs-path)
            FIPS_DEBS_PATH="$2"
            shift 2
            ;;
        --wolfssl-tag)
            WOLFSSL_TAG="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate arguments
if [ "$FIPS_MODE" = true ] && [ -n "$FIPS_DEBS_PATH" ] && [ ! -d "$FIPS_DEBS_PATH" ]; then
    echo "ERROR: FIPS debs directory not found: $FIPS_DEBS_PATH"
    exit 1
fi

echo "=== Building wolfProvider Debian packages ==="
echo "FIPS Mode: $FIPS_MODE"
if [ "$FIPS_MODE" = true ]; then
    echo "FIPS Debs Path: $FIPS_DEBS_PATH"
else
    echo "WolfSSL Tag: $WOLFSSL_TAG"
fi

# Install build dependencies
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    devscripts \
    debhelper \
    dh-autoreconf \
    libtool \
    pkg-config \
    git \
    wget \
    curl \
    ca-certificates \
    openssl \
    dpkg-dev \
    lintian \
    fakeroot \
    dh-exec \
    equivs \
    expect \
    xxd

# Ensure the working directory is safe
git config --global --add safe.directory "$PWD"

# Fetch tags (for Debian versioning)
git fetch --tags --force --prune

# Setup package directories
mkdir -p "/tmp/openssl-pkg"
mkdir -p "/tmp/wolfprov-pkg"
mkdir -p "/tmp/wolfprov-packages"

chmod +x debian/install-openssl.sh
chmod +x debian/install-wolfprov.sh

# Handle wolfSSL packages based on mode
if [ "$FIPS_MODE" = true ]; then
    echo "=== Using pre-built FIPS wolfSSL packages ==="
    
    # If no FIPS_DEBS_PATH specified, download from debs branch
    if [ -z "$FIPS_DEBS_PATH" ]; then
        echo "No local FIPS debs path specified, downloading from debs branch..."
        ORIGINAL_DIR="$PWD"
        DEBS_CHECKOUT_DIR=$(mktemp -d)
        
        echo "Checking out debs branch from $DEBS_REPO..."
        cd "$DEBS_CHECKOUT_DIR"
        
        # Clone with sparse checkout to only get the fips directory
        git clone --depth 1 --filter=blob:none --sparse "$DEBS_REPO" -b "$DEBS_BRANCH" wolfprovider-debs
        cd wolfprovider-debs
        git sparse-checkout set fips
        
        # Check if fips directory exists and has debs
        if [ ! -d "fips" ] || [ -z "$(ls -A fips/*.deb 2>/dev/null)" ]; then
            echo "ERROR: No FIPS packages found in debs branch"
            exit 1
        fi
        
        echo "Downloaded FIPS packages from debs branch:"
        ls -lh fips/*.deb
        
        # Copy FIPS debs directly to packages directory for installation
        cp fips/*.deb /tmp/wolfprov-packages/
        
        # Return to original directory and clean up checkout directory
        cd "$ORIGINAL_DIR"
        rm -rf "$DEBS_CHECKOUT_DIR"
    else
        echo "Using local FIPS debs from: $FIPS_DEBS_PATH"
        
        # Verify FIPS debs exist
        fips_debs=$(ls -1 "$FIPS_DEBS_PATH"/*.deb 2>/dev/null || true)
        if [ -z "$fips_debs" ]; then
            echo "ERROR: No .deb files found in $FIPS_DEBS_PATH"
            exit 1
        fi
        
        echo "Found FIPS packages:"
        ls -lh "$FIPS_DEBS_PATH"/*.deb
        
        # Copy FIPS debs directly to packages directory for installation
        # Only copy the FIPS versions (those with +commercial.fips in the name)
        cp "$FIPS_DEBS_PATH"/*commercial.fips*.deb /tmp/wolfprov-packages/
    fi
    
    echo "FIPS packages ready in /tmp/wolfprov-packages:"
    ls -lh /tmp/wolfprov-packages/
    
    echo "=== Installing FIPS wolfSSL packages ==="
    # Install wolfSSL FIPS packages now (before building OpenSSL/wolfProvider)
    # Use explicit filenames to ensure we install only FIPS packages
    echo "Installing FIPS wolfSSL library..."
    sudo dpkg -i /tmp/wolfprov-packages/libwolfssl_*commercial.fips*.deb || sudo apt install -f -y
    
    echo "Installing FIPS wolfSSL dev package..."
    sudo dpkg -i /tmp/wolfprov-packages/libwolfssl-dev_*commercial.fips*.deb || sudo apt install -f -y
    
    echo "Verifying installed wolfSSL packages are FIPS:"
    dpkg -l | grep wolfssl
    
    # Verify the FIPS packages are actually installed
    if ! dpkg -l | grep -q "libwolfssl.*commercial.fips"; then
        echo "ERROR: FIPS wolfSSL packages not properly installed!"
        echo "Expected packages with 'commercial.fips' in version"
        exit 1
    fi
    echo "SUCCESS: FIPS wolfSSL packages verified"
else
    echo "=== Building and installing wolfSSL from source (non-FIPS) ==="
    chmod +x debian/install-wolfssl.sh
    mkdir -p "/tmp/wolfssl-pkg"
    
    # Build wolfSSL from source
    ./debian/install-wolfssl.sh \
        --tag "$WOLFSSL_TAG" \
        "/tmp/wolfssl-pkg"
    
    # Copy built wolfSSL packages to packages directory
    find /tmp/wolfssl-pkg -name "*wolfssl*.deb" -type f -exec cp {} /tmp/wolfprov-packages/ \;
fi

# Install OpenSSL Debian packages
./debian/install-openssl.sh --replace-default "/tmp/openssl-pkg"

# Clean up any existing wolfProvider packages from previous runs
echo "Cleaning up previous wolfProvider build artifacts..."
rm -f /tmp/wolfprov-pkg/*.deb 2>/dev/null || true

# Build wolfProvider Debian packages (but don't install yet)
if [ "$FIPS_MODE" = true ]; then
    echo "=== Building wolfProvider with FIPS support ==="
    
    # Verify wolfSSL FIPS packages are still installed before building wolfProvider
    echo "Pre-build check: Verifying wolfSSL FIPS packages are still installed:"
    dpkg -l | grep wolfssl
    if ! dpkg -l | grep -q "libwolfssl.*commercial.fips"; then
        echo "WARNING: FIPS wolfSSL packages were replaced! Re-installing..."
        sudo dpkg -i /tmp/wolfprov-packages/libwolfssl_*commercial.fips*.deb || sudo apt install -f -y
        sudo dpkg -i /tmp/wolfprov-packages/libwolfssl-dev_*commercial.fips*.deb || sudo apt install -f -y
    fi
    
    ./debian/install-wolfprov.sh --fips "/tmp/wolfprov-pkg"
    
    # Verify wolfSSL FIPS packages are still installed after building wolfProvider
    echo "Post-build check: Verifying wolfSSL FIPS packages after wolfProvider build:"
    dpkg -l | grep wolfssl
else
    echo "=== Building wolfProvider (non-FIPS) ==="
    ./debian/install-wolfprov.sh "/tmp/wolfprov-pkg"
fi

# Collect wolfProvider package artifacts from the build output directory
echo "Collecting wolfProvider packages..."
if [ -d "/tmp/wolfprov-pkg" ]; then
    find /tmp/wolfprov-pkg -name "*.deb" -type f -exec cp {} /tmp/wolfprov-packages/ \;
fi

# Also check parent directory for packages
if ls ../*.deb 1> /dev/null 2>&1; then
    cp ../*.deb /tmp/wolfprov-packages/ 2>/dev/null || true
fi

echo "All packages in /tmp/wolfprov-packages:"
ls -lh /tmp/wolfprov-packages/

echo "=== Installing OpenSSL and wolfProvider packages ==="

# Install OpenSSL packages in dependency order with conflict resolution
libssl3_debs=$(ls -1 /tmp/wolfprov-packages/libssl3_[0-9]*.deb 2>/dev/null || true)
openssl_debs=$(ls -1 /tmp/wolfprov-packages/openssl_[0-9]*.deb 2>/dev/null || true)
libssl_dev_debs=$(ls -1 /tmp/wolfprov-packages/libssl-dev_[0-9]*.deb 2>/dev/null || true)

# Install custom OpenSSL packages
echo "Installing custom OpenSSL packages..."
if [ -n "$libssl3_debs" ]; then
  echo "Installing custom libssl3 package..."
  sudo dpkg -i $libssl3_debs || sudo apt install -f -y
fi
if [ -n "$openssl_debs" ]; then
  echo "Installing custom openssl package..."
  sudo dpkg -i $openssl_debs || sudo apt install -f -y
fi
if [ -n "$libssl_dev_debs" ]; then
  echo "Installing custom libssl-dev package..."
  sudo dpkg -i $libssl_dev_debs || sudo apt install -f -y
fi

# Install wolfProvider main package
wolfprov_main=$(ls -1 /tmp/wolfprov-packages/libwolfprov_[0-9]*.deb 2>/dev/null | head -n1 || true)
if [ -z "$wolfprov_main" ]; then
  echo "ERROR: libwolfprov main package not found"
  exit 1
fi
sudo dpkg -i "$wolfprov_main" || sudo apt install -f -y

# Verify installation
if [ "$FIPS_MODE" = true ]; then
    echo "=== Verifying FIPS installation ==="
    ./scripts/verify-install.sh --replace-default --fips
else
    echo "=== Verifying non-FIPS installation ==="
    ./scripts/verify-install.sh --replace-default
fi

echo "=== Replace Default installed! ==="