#!/bin/bash

#----openssh.sh----
#
# This script runs the OpenSSH tests against the FIPS wolfProvider.
# Environment variables OPENSSH_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
# TODO: Add FORCE_FAIL neg testing
set -e
set -x

# Use stable version instead of specific commit
OPENSSH_REF="V_10_0_P2"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/aidangarske/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"
OSP_DIR="$WOLFPROV_DIR/osp"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Clone OSP repo if it doesn't exist
if [ ! -d "$OSP_DIR" ]; then
    mkdir -p "$OSP_DIR"
    cd "$OSP_DIR"
    git clone --depth=1 https://github.com/wolfssl/osp.git .
    cd "$WOLFPROV_DIR"
fi

# Clone OpenSSH repo
rm -rf openssh-portable
git clone --depth=1 --branch="${OPENSSH_REF}" https://github.com/openssh/openssh-portable.git

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"

# Build OpenSSH
cd openssh-portable

# Apply the patch for the correct version of OpenSSH
if [ "${OPENSSH_REF}" != "master" ]; then
    patch -p1 < "${OSP_DIR}/wolfProvider/openssh/openssh-${OPENSSH_REF}-wolfprov.patch"
else
    # for master we need to supply the latest release version
    patch -p1 < "${OSP_DIR}/wolfProvider/openssh/openssh-V_10_0_P2-wolfprov.patch"
fi

autoreconf -ivf
./configure --with-ssl-dir="${OPENSSL_INSTALL}" \
            --with-rpath=-Wl,-rpath="${OPENSSL_INSTALL}/lib64" \
            --with-prngd-socket=/tmp/prngd
make -j

# Run all the tests except (t-exec) as it takes too long
make file-tests interop-tests extra-tests unit

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
