#!/bin/bash

#----grpc.sh----
#
# This script runs the gRPC tests against the FIPS wolfProvider.
# Environment variables GRPC_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
# TODO: Add FORCE_FAIL neg testing
set -e
set -x

# Use stable version instead of specific commit
GRPC_REF="v1.60.0"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/user/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

ldd --version

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Clone gRPC repo if it doesn't exist
rm -rf grpc
git clone --depth=1 --branch="${GRPC_REF}" https://github.com/grpc/grpc.git

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
export LDFLAGS="-L${OPENSSL_INSTALL}/lib64"
export CPPFLAGS="-I${OPENSSL_INSTALL}/include"

# Build gRPC
cd grpc
git submodule update --init
mkdir -p cmake/build
cd cmake/build
cmake -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DgRPC_SSL_PROVIDER=package \
  -DCMAKE_PREFIX_PATH="${WOLFSSL_INSTALL}" \
  -DOPENSSL_ROOT_DIR="${WOLFSSL_INSTALL}" \
  -DOPENSSL_INCLUDE_DIR="${WOLFSSL_INSTALL}/include" \
  -DOPENSSL_LIBRARIES="${WOLFSSL_INSTALL}/lib" \
  ../..

# Run specific SSL-related tests
make -j$(nproc) \
    bad_ssl_alpn_test \
    bad_ssl_cert_test \
    client_ssl_test \
    crl_ssl_transport_security_test \
    server_ssl_test \
    ssl_transport_security_test \
    ssl_transport_security_utils_test \
    test_cpp_end2end_ssl_credentials_test \
    h2_ssl_cert_test

cd ../.. # Back to grpc
# Start the port server
./tools/run_tests/start_port_server.py &

# Run the tests with debug output
for t in \
    bad_ssl_alpn_test \
    bad_ssl_cert_test \
    client_ssl_test \
    crl_ssl_transport_security_test \
    server_ssl_test \
    ssl_transport_security_test \
    ssl_transport_security_utils_test \
    test_cpp_end2end_ssl_credentials_test \
    h2_ssl_cert_test ; do
    echo "Running test: $t"
    GPRC_TRACE=all GPRC_VERBOSITY=DEBUG ./cmake/build/$t
done

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
