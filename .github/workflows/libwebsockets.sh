#!/bin/bash

#----libwebsockets.sh----
#
# This script runs the libwebsockets tests against the FIPS wolfProvider.
# Environment variables LIBWEBSOCKETS_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by the CI system or can be set manually.
set -e
set -x

# Use default version if not set
LIBWEBSOCKETS_REF="${LIBWEBSOCKETS_REF:-v4.3.3}"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/user/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"
LIBWEBSOCKETS_INSTALL="$WOLFPROV_DIR/libwebsockets-install"

cd "$WOLFPROV_DIR"

rm -rf libwebsockets
git clone --depth=1 --branch=${LIBWEBSOCKETS_REF} https://github.com/warmcat/libwebsockets.git libwebsockets

# Build libwebsockets
cd libwebsockets
mkdir -p build
cd build

# Configure with cmake, explicitly setting OpenSSL executable to system OpenSSL
cmake -DCMAKE_INSTALL_PREFIX="$LIBWEBSOCKETS_INSTALL" \
      -DCMAKE_BUILD_TYPE=Debug \
      -DLWS_WITH_SSL=ON \
      -DLWS_OPENSSL_INCLUDE_DIRS="${OPENSSL_INSTALL}/include" \
      -DLWS_OPENSSL_LIBRARIES="${OPENSSL_INSTALL}/lib64/libssl.so;${OPENSSL_INSTALL}/lib64/libcrypto.so" \
      -DOPENSSL_EXECUTABLE="/usr/bin/openssl" \
      ..

# Build libwebsockets
make -j$(nproc)

# Install libwebsockets
make install

# Source environment setup script for proper configuration
echo "Setting up environment..."
export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"

# Run libwebsockets tests
echo "Running libwebsockets tests..."

# Start the test server in background
echo "Starting libwebsockets test server..."
./bin/libwebsockets-test-server --port=11111 --ssl > server.log 2>&1 & 
SERVER_PID=$!

# Give server time to start
sleep 5

# Check if server is still running
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "Server failed to start, checking logs..."
    cat server.log
    exit 1
fi

# Run the test client
echo "Running libwebsockets test client..."
timeout 10 ./bin/libwebsockets-test-client 127.0.0.1 --port=11111 --ssl > client.log 2>&1 || CLIENT_RESULT=$?

# Check if wolfProvider is being used
echo "Checking if wolfProvider is loaded..."
ldd ./bin/libwebsockets-test-server | grep wolfProvider || echo "wolfProvider not found in server"
ldd ./bin/libwebsockets-test-client | grep wolfProvider || echo "wolfProvider not found in client"

# Stop the server
kill $SERVER_PID 2>/dev/null || echo "Server already exited"

# Display logs
echo "=== Server Log ==="
cat server.log
echo "=== Client Log ==="
cat client.log

# Combine logs for analysis
cat server.log client.log > libwebsockets-test.log

# Check if client connected successfully
if grep -q "CLIENT_ESTABLISHED" libwebsockets-test.log; then
    echo "SUCCESS: Client connected successfully"
else
    echo "ERROR: Client failed to connect"
    exit 1
fi
