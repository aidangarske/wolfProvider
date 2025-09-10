#!/bin/bash
#
# install-replace-default.sh
#
# Copyright (C) 2025 wolfSSL Inc.
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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1335, USA
#

# Simple script to install wolfProvider as system OpenSSL replacement
# This assumes wolfProvider has already been built with --replace-default
# and simply moves the built libraries to system locations

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "[*] Installing wolfProvider as system OpenSSL replacement"

# Function to determine the correct lib directory for the architecture
get_lib_dir() {
    if command -v dpkg-architecture >/dev/null 2>&1; then
        DEB_HOST_MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo "x86_64-linux-gnu")
        echo "/usr/lib/${DEB_HOST_MULTIARCH}"
    else
        # Fallback for non-Debian systems
        echo "/usr/lib/x86_64-linux-gnu"
    fi
}

# Detect architecture-specific paths
LIBDIR=$(get_lib_dir)
INCLUDEDIR="/usr/include/openssl"
BINDIR="/usr/bin"

echo "[*] Using library directory: $LIBDIR"

# Detect the openssl installation directory from wolfProvider build
if [ -d "$REPO_ROOT/openssl-install/lib" ]; then
    OPENSSL_BUILD_LIBDIR="$REPO_ROOT/openssl-install/lib"
elif [ -d "$REPO_ROOT/openssl-install/lib64" ]; then
    OPENSSL_BUILD_LIBDIR="$REPO_ROOT/openssl-install/lib64"
else
    echo "ERROR: Could not find OpenSSL build output directory"
    echo "Expected: $REPO_ROOT/openssl-install/lib or $REPO_ROOT/openssl-install/lib64"
    echo "Make sure wolfProvider has been built with --replace-default first"
    exit 1
fi

OPENSSL_BUILD_DIR="$REPO_ROOT/openssl-install"

# Verify required files exist
if [ ! -f "$OPENSSL_BUILD_LIBDIR/libcrypto.so" ]; then
    echo "ERROR: libcrypto.so not found in $OPENSSL_BUILD_LIBDIR"
    echo "Make sure wolfProvider has been built with --replace-default first"
    exit 1
fi

if [ ! -f "$OPENSSL_BUILD_LIBDIR/libssl.so" ]; then
    echo "ERROR: libssl.so not found in $OPENSSL_BUILD_LIBDIR"
    echo "Make sure wolfProvider has been built with --replace-default first"
    exit 1
fi

echo "[*] Installing libraries into $LIBDIR"
sudo cp -av "$OPENSSL_BUILD_LIBDIR"/libcrypto.so* "$LIBDIR/"
sudo cp -av "$OPENSSL_BUILD_LIBDIR"/libssl.so* "$LIBDIR/"

echo "[*] Installing headers into $INCLUDEDIR"
sudo mkdir -p "$INCLUDEDIR"
sudo cp -av "$OPENSSL_BUILD_DIR/include/openssl"/* "$INCLUDEDIR/"

# Install OpenSSL CLI if it exists
if [ -f "$OPENSSL_BUILD_DIR/bin/openssl" ]; then
    echo "[*] Installing OpenSSL CLI into $BINDIR"
    sudo cp -av "$OPENSSL_BUILD_DIR/bin/openssl" "$BINDIR/openssl"
else
    echo "[*] OpenSSL CLI not found, skipping"
fi

# Install pkg-config files if they exist
if [ -d "$OPENSSL_BUILD_LIBDIR/pkgconfig" ]; then
    echo "[*] Installing pkg-config files"
    sudo mkdir -p "$LIBDIR/pkgconfig"
    sudo cp -av "$OPENSSL_BUILD_LIBDIR/pkgconfig"/*.pc "$LIBDIR/pkgconfig/"
fi

# Refresh linker cache
echo "[*] Running ldconfig to refresh library cache"
sudo ldconfig

echo "[*] wolfProvider is now the default system OpenSSL"
echo "[*] System libraries:"
echo "    libcrypto.so: $LIBDIR/libcrypto.so"
echo "    libssl.so: $LIBDIR/libssl.so"
echo "    Headers: $INCLUDEDIR/"
echo "    Binary: $BINDIR/openssl"

# Verify installation
echo "[*] Verifying installation..."
if command -v openssl >/dev/null 2>&1; then
    OPENSSL_VERSION=$(openssl version 2>/dev/null || echo "Failed to get version")
    echo "    OpenSSL version: $OPENSSL_VERSION"
else
    echo "    WARNING: OpenSSL binary not found in PATH"
fi

# Test if we can load providers (wolfProvider should be default now)
if openssl list -providers >/dev/null 2>&1; then
    echo "    SUCCESS: OpenSSL can list providers"
    if openssl list -providers 2>/dev/null | grep -q "wolfProvider"; then
        echo "    SUCCESS: wolfProvider is loaded as default provider"
    else
        echo "    INFO: wolfProvider may not be visible in provider list (this can be normal for replace-default mode)"
    fi
else
    echo "    WARNING: OpenSSL provider listing failed"
fi

echo "[*] Installation complete!"
