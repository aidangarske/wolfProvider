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
USER=$(whoami)
WOLFPROV_DIR="/home/$USER/wolfProvider"

# Clone OpenLDAP repo
rm -rf openldap
git clone --depth=1 --branch="${OPENLDAP_REF}" https://github.com/openldap/openldap.git

# Build OpenLDAP
cd openldap
rm -f aclocal.m4
autoreconf -ivf

openssl list -providers
openssl list -providers | grep -q "wolfSSL Provider" || (echo "ERROR: libwolfprov not found in OpenSSL providers" && exit 1)

# Configure with OpenSSL
./configure --with-tls=openssl \
            --disable-bdb \
            --disable-hdb

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