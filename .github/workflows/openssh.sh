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
WOLFPROV_DIR="/home/user/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/usr"
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
export FIPS_MODE=1

# Build OpenSSH
cd openssh-portable

patch -p1 < "${WOLFPROV_DIR}/patch2.diff"

autoreconf -ivf
./configure --with-ssl-dir="${OPENSSL_INSTALL}" \
            --with-rpath=-Wl,-rpath="${OPENSSL_INSTALL}/lib64" \
            --disable-security-key-builtin \
            --with-prngd-socket=/tmp/prngd
make -j CFLAGS="-DFIPS_MODE=1"

# Run all the tests except (t-exec) as it takes too long
make CFLAGS="-DFIPS_MODE=1" file-tests extra-tests unit

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
