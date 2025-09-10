#!/bin/bash
#
# install-openssl-global.sh
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

# Script to install OpenSSL globally with wolfProvider as the default provider
# This ensures there is only one libcrypto.so on the system (the patched one)
# and that WPFF works with system defaults without needing to source env

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LOG_FILE=${SCRIPT_DIR}/install-openssl-global.log

# Source utility functions
source ${SCRIPT_DIR}/utils-openssl.sh
source ${SCRIPT_DIR}/utils-wolfprovider.sh

# Global installation paths
GLOBAL_OPENSSL_PREFIX="/usr"
GLOBAL_OPENSSL_LIBDIR="/usr/lib/x86_64-linux-gnu"  # Default for Ubuntu/Debian
GLOBAL_OPENSSL_OPENSSLDIR="/usr/lib/ssl"

# Function to determine the correct lib directory
get_lib_dir() {
    if command -v dpkg-architecture >/dev/null 2>&1; then
        DEB_HOST_MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo "x86_64-linux-gnu")
        echo "/usr/lib/${DEB_HOST_MULTIARCH}"
    else
        echo "/usr/lib/x86_64-linux-gnu"
    fi
}

# Function to backup existing OpenSSL installation
backup_existing_openssl() {
    printf "\nBacking up existing OpenSSL installation...\n"
    
    # Create backup directory with timestamp
    BACKUP_DIR="/tmp/openssl-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup existing libraries
    if [ -f "${GLOBAL_OPENSSL_LIBDIR}/libcrypto.so" ]; then
        printf "\tBacking up libcrypto.so...\n"
        cp -r ${GLOBAL_OPENSSL_LIBDIR}/libcrypto.so* "$BACKUP_DIR/" 2>/dev/null || true
    fi
    
    if [ -f "${GLOBAL_OPENSSL_LIBDIR}/libssl.so" ]; then
        printf "\tBacking up libssl.so...\n"
        cp -r ${GLOBAL_OPENSSL_LIBDIR}/libssl.so* "$BACKUP_DIR/" 2>/dev/null || true
    fi
    
    # Backup openssl binary
    if [ -f "${GLOBAL_OPENSSL_PREFIX}/bin/openssl" ]; then
        printf "\tBacking up openssl binary...\n"
        cp ${GLOBAL_OPENSSL_PREFIX}/bin/openssl "$BACKUP_DIR/" 2>/dev/null || true
    fi
    
    printf "\tBackup created at: $BACKUP_DIR\n"
    echo "$BACKUP_DIR" > /tmp/openssl-backup-location
}

# Function to restore backed up OpenSSL installation
restore_openssl() {
    if [ -f /tmp/openssl-backup-location ]; then
        BACKUP_DIR=$(cat /tmp/openssl-backup-location)
        if [ -d "$BACKUP_DIR" ]; then
            printf "\nRestoring original OpenSSL installation from $BACKUP_DIR...\n"
            
            # Restore libraries
            if [ -f "$BACKUP_DIR/libcrypto.so" ]; then
                printf "\tRestoring libcrypto.so...\n"
                sudo cp -r "$BACKUP_DIR"/libcrypto.so* ${GLOBAL_OPENSSL_LIBDIR}/ 2>/dev/null || true
            fi
            
            if [ -f "$BACKUP_DIR/libssl.so" ]; then
                printf "\tRestoring libssl.so...\n"
                sudo cp -r "$BACKUP_DIR"/libssl.so* ${GLOBAL_OPENSSL_LIBDIR}/ 2>/dev/null || true
            fi
            
            # Restore openssl binary
            if [ -f "$BACKUP_DIR/openssl" ]; then
                printf "\tRestoring openssl binary...\n"
                sudo cp "$BACKUP_DIR/openssl" ${GLOBAL_OPENSSL_PREFIX}/bin/ 2>/dev/null || true
            fi
            
            printf "\tRestoration complete.\n"
        fi
    fi
}

# Function to install OpenSSL globally
install_openssl_global() {
    printf "\nInstalling OpenSSL ${OPENSSL_TAG} globally with wolfProvider as default provider...\n"
    
    # Set replace default mode
    WOLFPROV_REPLACE_DEFAULT=1
    
    # Clone and patch OpenSSL
    clone_openssl
    patch_openssl
    check_openssl_replace_default_mismatch

    pushd ${OPENSSL_SOURCE_DIR} &> /dev/null

    # Determine the correct lib directory
    GLOBAL_OPENSSL_LIBDIR=$(get_lib_dir)
    printf "\tUsing lib directory: ${GLOBAL_OPENSSL_LIBDIR}\n"

    # Build configure command for global installation
    CONFIG_CMD="./config shared"
    CONFIG_CMD+=" --prefix=${GLOBAL_OPENSSL_PREFIX}"
    CONFIG_CMD+=" --openssldir=${GLOBAL_OPENSSL_OPENSSLDIR}"
    CONFIG_CMD+=" --libdir=${GLOBAL_OPENSSL_LIBDIR}"

    if [ "$WOLFPROV_DEBUG" = "1" ]; then
        CONFIG_CMD+=" enable-trace --debug"
    fi

    # For replace default, skip tests
    CONFIG_CMD+=" no-external-tests no-tests"

    printf "\tConfigure OpenSSL ${OPENSSL_TAG} for global installation... "
    $CONFIG_CMD >>$LOG_FILE 2>&1
    RET=$?
    if [ $RET != 0 ]; then
        printf "ERROR.\n"
        printf "\tConfiguration failed. Check $LOG_FILE for details.\n"
        popd &> /dev/null
        exit 1
    fi
    printf "Done.\n"

    printf "\tBuild OpenSSL ${OPENSSL_TAG} ... "
    make -j$NUMCPU >>$LOG_FILE 2>&1
    if [ $? != 0 ]; then
        printf "ERROR.\n"
        printf "\tBuild failed. Check $LOG_FILE for details.\n"
        popd &> /dev/null
        exit 1
    fi
    printf "Done.\n"

    # Install OpenSSL globally (requires sudo)
    printf "\tInstalling OpenSSL ${OPENSSL_TAG} globally (requires sudo)... "
    
    # Install libraries
    sudo cp libcrypto.so* ${GLOBAL_OPENSSL_LIBDIR}/
    sudo cp libssl.so* ${GLOBAL_OPENSSL_LIBDIR}/
    
    # Install openssl binary
    sudo cp apps/openssl ${GLOBAL_OPENSSL_PREFIX}/bin/openssl
    
    # Install headers
    sudo mkdir -p ${GLOBAL_OPENSSL_PREFIX}/include/openssl
    sudo cp -r include/openssl/* ${GLOBAL_OPENSSL_PREFIX}/include/openssl/
    
    # Install pkg-config files
    sudo mkdir -p ${GLOBAL_OPENSSL_LIBDIR}/pkgconfig
    sudo cp *.pc ${GLOBAL_OPENSSL_LIBDIR}/pkgconfig/
    
    # Update library cache
    sudo ldconfig
    
    printf "Done.\n"

    popd &> /dev/null
    
    printf "\nOpenSSL ${OPENSSL_TAG} installed globally with wolfProvider as default provider.\n"
    printf "System now has only one libcrypto.so: ${GLOBAL_OPENSSL_LIBDIR}/libcrypto.so\n"
    printf "WPFF should now work with system defaults without sourcing environment variables.\n"
}

# Function to verify global installation
verify_global_installation() {
    printf "\nVerifying global OpenSSL installation...\n"
    
    # Check if OpenSSL binary works
    if command -v openssl >/dev/null 2>&1; then
        OPENSSL_VERSION=$(openssl version 2>/dev/null || echo "Failed to get version")
        printf "\tOpenSSL version: $OPENSSL_VERSION\n"
    else
        printf "\tERROR: OpenSSL binary not found in PATH\n"
        return 1
    fi
    
    # Check if libraries are in place
    if [ -f "${GLOBAL_OPENSSL_LIBDIR}/libcrypto.so" ]; then
        printf "\tlibcrypto.so found at: ${GLOBAL_OPENSSL_LIBDIR}/libcrypto.so\n"
    else
        printf "\tERROR: libcrypto.so not found at expected location\n"
        return 1
    fi
    
    if [ -f "${GLOBAL_OPENSSL_LIBDIR}/libssl.so" ]; then
        printf "\tlibssl.so found at: ${GLOBAL_OPENSSL_LIBDIR}/libssl.so\n"
    else
        printf "\tERROR: libssl.so not found at expected location\n"
        return 1
    fi
    
    # Test that OpenSSL can load wolfProvider
    printf "\tTesting wolfProvider integration...\n"
    if openssl list -providers 2>/dev/null | grep -q "wolfProvider"; then
        printf "\tSUCCESS: wolfProvider is loaded as default provider\n"
    else
        printf "\tWARNING: wolfProvider may not be loaded as default provider\n"
        printf "\tThis may be expected if wolfProvider is not yet built/installed\n"
    fi
    
    printf "\tGlobal installation verification complete.\n"
}

# Main execution
main() {
    printf "OpenSSL Global Installation Script\n"
    printf "==================================\n"
    
    # Check if running as root (not recommended, but check anyway)
    if [ "$EUID" -eq 0 ]; then
        printf "WARNING: Running as root. This is not recommended.\n"
        printf "The script will use sudo for installation steps.\n"
    fi
    
    # Check if we have required environment variables
    if [ -z "$OPENSSL_TAG" ]; then
        printf "ERROR: OPENSSL_TAG environment variable not set\n"
        printf "Please set OPENSSL_TAG to the desired OpenSSL version (e.g., openssl-3.5.0)\n"
        exit 1
    fi
    
    # Backup existing installation
    backup_existing_openssl
    
    # Install OpenSSL globally
    install_openssl_global
    
    # Verify installation
    verify_global_installation
    
    printf "\nInstallation complete!\n"
    printf "To restore the original OpenSSL installation, run:\n"
    printf "  sudo $0 --restore\n"
}

# Handle command line arguments
case "${1:-}" in
    --restore)
        restore_openssl
        exit 0
        ;;
    --help|-h)
        printf "Usage: $0 [--restore|--help]\n"
        printf "\n"
        printf "  --restore    Restore the original OpenSSL installation from backup\n"
        printf "  --help       Show this help message\n"
        printf "\n"
        printf "Environment variables:\n"
        printf "  OPENSSL_TAG  OpenSSL version to install (required)\n"
        printf "  WOLFPROV_DEBUG  Set to 1 for debug output\n"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        printf "Unknown option: $1\n"
        printf "Use --help for usage information\n"
        exit 1
        ;;
esac
