#!/bin/bash

#----openldap.sh----
#
# This script runs the OpenLDAP tests against the FIPS wolfProvider.
# Environment variables OPENLDAP_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
# TODO: Add FORCE_FAIL neg testing
set -e
set -x

# Use stable version instead of specific commit
OPENLDAP_REF="OPENLDAP_REL_ENG_2_6_7"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/aidangarske/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Clone OpenLDAP repo
rm -rf openldap
git clone --depth=1 --branch="${OPENLDAP_REF}" https://github.com/openldap/openldap.git

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"

# Build OpenLDAP
cd openldap
rm -f aclocal.m4
autoreconf -ivf

# Configure with OpenSSL
./configure --with-tls=openssl \
            --disable-bdb \
            --disable-hdb \
            CFLAGS="-I${OPENSSL_INSTALL}/include -L${OPENSSL_INSTALL}/lib64" \
            LDFLAGS="-Wl,-rpath,${OPENSSL_INSTALL}/lib64"

# Build and test
make -j depend
make -j
make -j check

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
