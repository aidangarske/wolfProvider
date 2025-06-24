#!/bin/bash

#----net-snmp.sh----
#
# This script runs the net-snmp tests against the FIPS wolfProvider.
# Environment variables NET_SNMP_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
# TODO: Add FORCE_FAIL neg testing
set -e
set -x

# Use stable version instead of specific commit
NET_SNMP_REF="v5.9.3"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/user/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="/usr"  # Use system OpenSSL
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

netstat --version

# Clone net-snmp repo
rm -rf net-snmp
git clone --depth=1 --branch="${NET_SNMP_REF}" https://github.com/net-snmp/net-snmp.git
cd net-snmp

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"

# Debug: Check if OpenSSL is found
echo "Checking OpenSSL installation..."
pkg-config --list-all | grep -i openssl
pkg-config --cflags openssl
pkg-config --libs openssl

# Build net-snmp
autoreconf -ivf
./configure --disable-shared --disable-md5 --disable-des \
            --with-openssl="${OPENSSL_INSTALL}" \
            --with-default-snmp-version="3" \
            --with-sys-contact="@@no.where" \
            --with-sys-location="Unknown" \
            --with-logfile="/var/log/snmpd.log" \
            --with-persistent-directory="/var/net-snmp" \
            LDFLAGS="-L${OPENSSL_INSTALL}/lib64 -lcrypto -lssl" \
            CPPFLAGS="-I${OPENSSL_INSTALL}/include" \
            LIBS="-lcrypto -lssl"
make -j$(nproc)

# Run tests
autoconf --version | grep -P '2\.\d\d' -o > dist/autoconf-version
make -j test TESTOPTS="-e agentxperl"

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
