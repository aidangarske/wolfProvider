#!/bin/bash

#----ppp.sh----
#
# This script runs the PPP tests against the FIPS wolfProvider.
# Environment variables PPP_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by the CI system or can be set manually.
set -e
set -x

# Use default version if not set
PPP_REF="v2.5.2"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/user/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"
PPP_INSTALL="$WOLFPROV_DIR/ppp-install"

cd "$WOLFPROV_DIR"

# Clone PPP repo
rm -rf ppp_repo
git clone --depth=1 --branch "$PPP_REF" https://github.com/ppp-project/ppp.git ppp_repo

# Set up the environment for wolfProvider
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"
"${OPENSSL_INSTALL}/bin/openssl" list -providers

cd ppp_repo

patch -p1 < ../ppp.patch

# Build and install PPP
autoreconf -fiv
CPPFLAGS="-I${OPENSSL_INSTALL}/include" \
./configure --prefix="$PPP_INSTALL" \
    --with-openssl="$OPENSSL_INSTALL" \
    --disable-microsoft-extensions \
    --enable-wolfprov-fips
make -j$(nproc)
make install

# Run PPP tests
make check

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
