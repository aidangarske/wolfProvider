#!/bin/bash

#----iperf.sh----
#
# This script runs the iperf tests against the FIPS wolfProvider.
# Environment variables IPERF_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
IPERF_REF="3.12"

# Define base directories for cleaner paths
WOLFPROV_DIR="/home/user/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Clone iperf repo
rm -rf iperf
git clone --depth=1 --branch="${IPERF_REF}" https://github.com/esnet/iperf.git

# Build iperf
cd iperf

# Configure with OpenSSL
./configure --with-openssl="${OPENSSL_INSTALL}"

# Build iperf
make -j

# Generate RSA keys for testing
export KEY_DIR="$WOLFPROV_DIR/test-keys"
mkdir -p "$KEY_DIR"
cd "$KEY_DIR"

# Generate RSA keys for iperf tests
"${OPENSSL_INSTALL}/bin/openssl" genrsa -out rsa_private_unprotected.pem 2048
"${OPENSSL_INSTALL}/bin/openssl" rsa -in rsa_private_unprotected.pem -out rsa_private.pem -aes256 -passout 'pass:password'
"${OPENSSL_INSTALL}/bin/openssl" rsa -in rsa_private.pem -pubout -out rsa_public.pem -passin 'pass:password'

# Create credentials file for iperf authentication
# Username: mario, Password: rossi
echo "mario,bf7a49a846d44b454a5d11e7acfaf13d138bbe0b7483aa3e050879700572709b" > credentials.csv

# Go back to iperf directory
cd "$WOLFPROV_DIR/iperf"

# Set environment variables
export LD_LIBRARY_PATH="${WOLFSSL_INSTALL}/lib:${OPENSSL_INSTALL}/lib64"
export OPENSSL_CONF="${WOLFPROV_DIR}/provider-fips.conf"
export OPENSSL_MODULES="${WOLFPROV_INSTALL}/lib"
export PKG_CONFIG_PATH="${OPENSSL_INSTALL}/lib64/pkgconfig"
"${OPENSSL_INSTALL}/bin/openssl" list -providers

# Test variables for iperf
export IPERF3_EXECUTABLE="$WOLFPROV_DIR/iperf/src/iperf3"
export IPERF3_LIB="$WOLFPROV_DIR/iperf/src/.libs/libiperf.so"
export IPERF3_TEST_INTERVAL=0.1
export IPERF3_TEST_DURATION=10
export IPERF3_TEST_LOG="iperf-test.log"
export IPERF3_USER="mario"
export IPERF3_PASSWORD="rossi"

# Verify iperf loads OpenSSL containing wolfProvider
echo "Checking iperf library dependencies..."
ldd $IPERF3_LIB | grep -E '(wolfProvider|libwolfprov)' || echo "No wolfProvider found in library dependencies"

# Launch the iperf server in the background
echo "Starting iperf server..."

# Kill any existing iperf processes and wait for port to be free
echo "Cleaning up any existing iperf processes..."
pkill -f iperf3 || true
sleep 2

# Start the server
"$IPERF3_EXECUTABLE" -s \
  --rsa-private-key-path "$KEY_DIR/rsa_private_unprotected.pem" \
  --authorized-users-path "$KEY_DIR/credentials.csv" &

SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Give server time to start and check if it's running
sleep 3
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "Server failed to start properly"
    exit 1
fi

# Run the client
echo "Running iperf client..."
"$IPERF3_EXECUTABLE" -c localhost -i "$IPERF3_TEST_INTERVAL" -t "$IPERF3_TEST_DURATION" \
  --rsa-public-key-path "$KEY_DIR/rsa_public.pem" \
  --user "$IPERF3_USER" | tee "$IPERF3_TEST_LOG"

CLIENT_EXIT_CODE=$?

# Clean up server process
echo "Cleaning up server process..."
kill $SERVER_PID 2>/dev/null || true
wait $SERVER_PID 2>/dev/null || true

# Check results
if [ $CLIENT_EXIT_CODE -eq 0 ]; then
  echo "iperf tests completed successfully"
  echo "Workflow completed successfully"
else
  echo "iperf tests failed"
  echo "Workflow failed"
  exit 1
fi
