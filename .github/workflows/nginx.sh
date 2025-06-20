#!/bin/bash

#----nginx.sh----
#
# This script runs the nginx tests against the FIPS wolfProvider.
# Environment variables NGINX_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
# TODO: Add FORCE_FAIL neg testing
set -e
set -x

# Use stable version instead of specific commit
NGINX_REF="release-1.27.4"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/aidangarske/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Clone nginx repo
rm -rf nginx
git clone --depth=1 --branch="${NGINX_REF}" https://github.com/nginx/nginx.git

# Build nginx
cd nginx
./auto/configure --with-http_ssl_module --with-stream --with-stream_ssl_module --with-stream_ssl_preread_module --with-http_v2_module --with-mail --with-mail_ssl_module
make -j$(nproc)

# Clone nginx-tests repo
cd ..
rm -rf nginx-tests
git clone --depth=1 --branch=master https://github.com/nginx/nginx-tests.git

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"

# Run nginx tests
cd nginx-tests
patch -p1 < ../nginx-test.patch

TEST_NGINX_VERBOSE=y TEST_NGINX_CATLOG=y TEST_NGINX_BINARY=../nginx/objs/nginx prove -v .

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
