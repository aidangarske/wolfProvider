#!/bin/bash

#----tcpdump.sh----
#
# This script runs the tcpdump tests against the FIPS wolfProvider.
# Environment variables TCPDUMP_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
TCPDUMP_REF="tcpdump-4.99.3"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/user/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"
LIBPCAP_INSTALL="$WOLFPROV_DIR/libpcap-install"
TCPDUMP_INSTALL="$WOLFPROV_DIR/tcpdump-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Clone and build libpcap (required dependency for tcpdump)
rm -rf libpcap
git clone --depth=1 https://github.com/the-tcpdump-group/libpcap.git
cd libpcap
./autogen.sh
./configure --prefix="$LIBPCAP_INSTALL"
make -j
make install
cd ..

# Clone tcpdump repo
rm -rf tcpdump
git clone --depth=1 --branch="${TCPDUMP_REF}" https://github.com/the-tcpdump-group/tcpdump.git

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${LIBPCAP_INSTALL}/lib/pkgconfig:${OPENSSL_INSTALL}/lib64/pkgconfig"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"

# Build tcpdump
cd tcpdump

patch -p1 < ../tcpdump-fips-patch.diff

autoreconf -fiv

./configure --prefix="$TCPDUMP_INSTALL" \
            --with-pcap="$LIBPCAP_INSTALL" \
            --enable-wolfprov-fips --enable-crypto

# Build tcpdump
make -j

# Set up the environment for wolfProvider (equivalent to source scripts/env-setup)
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64:$LD_LIBRARY_PATH"

# Run tests
make check 2>&1 | tee tcpdump-test.log
TEST_RESULT=$?

if [ $TEST_RESULT -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
