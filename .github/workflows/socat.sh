#!/bin/bash

#----socat.sh----
#
# This script runs the socat tests against the FIPS wolfProvider.
# Environment variables SOCAT_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/aidangarske/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Download and extract socat
curl -O http://www.dest-unreach.org/socat/download/socat-1.8.0.0.tar.gz
tar xvf socat-1.8.0.0.tar.gz

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"
export SHELL=/bin/bash

# Build socat
cd socat-1.8.0.0
./configure --enable-openssl-base="${OPENSSL_INSTALL}" --enable-fips
make -j$(nproc)

# Verify OpenSSL loads wolfProvider
"${OPENSSL_INSTALL}/bin/openssl" list -providers

# Show socat version (includes OpenSSL version info)
./socat -V

# Add expected 311 and 313 failures
# Run the tests with expected failures 
SOCAT="${WOLFPROV_DIR}/socat-1.8.0.0/socat" ./test.sh -t 0.5 --expect-fail 36,64,146,214,216,217,309,310,386,399,402,403,459,460,467,468,475,478,491,492,528,529,530

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
