#!/bin/bash
# rsa-cmd-test.sh
# RSA key generation and sign/verify test for wolfProvider
#
# Copyright (C) 2006-2024 wolfSSL Inc.
#
# This file is part of wolfProvider.
#
# wolfProvider is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# wolfProvider is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1335, USA

# Set up environment
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd )"
UTILS_DIR="${REPO_ROOT}/scripts"
export LOG_FILE="${SCRIPT_DIR}/rsa-test.log"
touch "$LOG_FILE"

# Source wolfProvider utilities
source "${UTILS_DIR}/utils-general.sh"
source "${UTILS_DIR}/utils-openssl.sh"
source "${UTILS_DIR}/utils-wolfssl.sh"
source "${UTILS_DIR}/utils-wolfprovider.sh"

# Initialize the environment
init_wolfprov

# Verify wolfProvider is properly loaded
echo -e "\nVerifying wolfProvider configuration:"
if ! openssl list -providers | grep -q "libwolfprov"; then
    echo "[FAIL] wolfProvider not found in OpenSSL providers!"
    echo "Current provider list:"
    openssl list -providers
    exit 1
fi
echo "[PASS] wolfProvider is properly configured"

# Print environment for verification
echo "Environment variables:"
echo "OPENSSL_MODULES: ${OPENSSL_MODULES}"
echo "LD_LIBRARY_PATH: ${LD_LIBRARY_PATH}"

# Create test directories
mkdir -p rsa_outputs

# Create test data for signing
echo "This is test data for RSA signing and verification." > rsa_outputs/test_data.txt

# Array of RSA key sizes to test
KEY_SIZES=("2048" "3072" "4096")

echo "=== Running RSA Key Generation Tests ==="

# Function to validate key using only the default provider
validate_key() {
    local key_size=$1
    local key_file="rsa_outputs/rsa_wolf_${key_size}.pem"
    local pub_key_file="rsa_outputs/rsa_wolf_${key_size}_pub.pem"
    local data_file="rsa_outputs/test_data.txt"
    local sig_file="rsa_outputs/default_signature_${key_size}.bin"
    local priv_modulus_file="rsa_outputs/priv_modulus_${key_size}.txt"
    local pub_modulus_file="rsa_outputs/pub_modulus_${key_size}.txt"
    
    echo -e "\n=== Validating RSA-${key_size} Key with Default Provider ==="
    
    # Test 1: Check if key can be parsed with -text -noout
    echo "Test 1: Parsing key with -text -noout..."
    if ! openssl rsa -in "$key_file" -text -noout \
        -provider default -passin pass: > /dev/null 2>&1; then
        echo "[FAIL] RSA-${key_size} key parsing with -text -noout failed"
        exit 1
    fi
    echo "[PASS] RSA-${key_size} key parsing with -text -noout successful"
    
    # Test 2: Check if -modulus option works and matches between private and public keys
    echo "Test 2: Checking -modulus option..."
    
    # Get modulus from private key
    openssl rsa -in "$key_file" -modulus -noout \
        -provider default -passin pass: > "$priv_modulus_file"
    
    if [ ! -s "$priv_modulus_file" ]; then
        echo "[FAIL] RSA-${key_size} modulus extraction from private key failed"
        exit 1
    fi
    
    # Extract public key for verification using default provider
    openssl rsa -in "$key_file" -pubout \
        -provider default -passin pass: \
        -out "$pub_key_file"
    
    if [ ! -s "$pub_key_file" ]; then
        echo "[FAIL] RSA-${key_size} public key extraction failed"
        exit 1
    fi
    
    # Get modulus from public key
    openssl rsa -pubin -in "$pub_key_file" -modulus -noout \
        -provider default > "$pub_modulus_file"
    
    if [ ! -s "$pub_modulus_file" ]; then
        echo "[FAIL] RSA-${key_size} modulus extraction from public key failed"
        exit 1
    fi
    
    # Compare moduli
    if ! cmp -s "$priv_modulus_file" "$pub_modulus_file"; then
        echo "[FAIL] RSA-${key_size} moduli from private and public keys don't match"
        echo "Private key modulus: $(cat "$priv_modulus_file")"
        echo "Public key modulus: $(cat "$pub_modulus_file")"
        exit 1
    fi
    echo "[PASS] RSA-${key_size} moduli from private and public keys match"
    
    # Test 3: Sign/verify test
    echo "Test 3: Sign/verify test..."
    
    # Sign data with default provider
    echo "Signing data with default provider..."
    openssl dgst -sha256 -sign "$key_file" \
        -provider default -passin pass: \
        -out "$sig_file" "$data_file"
    
    if [ ! -s "$sig_file" ]; then
        echo "[FAIL] RSA-${key_size} signing with default provider failed"
        exit 1
    fi
    
    # Verify signature with default provider
    echo "Verifying signature with default provider..."
    openssl dgst -sha256 -verify "$pub_key_file" \
        -provider default \
        -signature "$sig_file" "$data_file"
    
    if [ $? -eq 0 ]; then
        echo "[PASS] Default provider: RSA-${key_size} sign/verify successful"
    else
        echo "[FAIL] Default provider: RSA-${key_size} sign/verify failed"
        exit 1
    fi
}

# Function to test interoperability between wolfProvider and OpenSSL
test_sign_verify_interop() {
    local key_size=$1
    local key_file="rsa_outputs/rsa_wolf_${key_size}.pem"
    local pub_key_file="rsa_outputs/rsa_wolf_${key_size}_pub.pem"
    local data_file="rsa_outputs/test_data.txt"
    local wolf_sig_file="rsa_outputs/wolf_signature_${key_size}.bin"
    local openssl_sig_file="rsa_outputs/openssl_signature_${key_size}.bin"
    
    echo -e "\n=== Testing RSA-${key_size} Sign/Verify Interoperability ==="
    
    # Extract public key for verification
    openssl rsa -in "$key_file" -pubout \
        -provider-path $WOLFPROV_PATH -provider libwolfprov \
        -out "$pub_key_file"
    
    # Test 1: Sign with wolfProvider, verify with OpenSSL default
    echo "Test 1: Sign with wolfProvider, verify with OpenSSL default"
    
    # Sign data with wolfProvider
    echo "Signing data with wolfProvider..."
    openssl dgst -sha256 -sign "$key_file" \
        -provider-path $WOLFPROV_PATH -provider libwolfprov \
        -out "$wolf_sig_file" "$data_file"
    
    if [ ! -s "$wolf_sig_file" ]; then
        echo "[FAIL] RSA-${key_size} signing with wolfProvider failed"
        exit 1
    fi
    
    # Verify signature with OpenSSL default
    echo "Verifying signature with OpenSSL default..."
    openssl dgst -sha256 -verify "$pub_key_file" \
        -provider default \
        -signature "$wolf_sig_file" "$data_file"
    
    if [ $? -eq 0 ]; then
        echo "[PASS] Interop: wolfProvider sign, OpenSSL verify successful"
    else
        echo "[FAIL] Interop: wolfProvider sign, OpenSSL verify failed"
        exit 1
    fi
    
    # Test 2: Sign with OpenSSL default, verify with wolfProvider
    echo -e "\nTest 2: Sign with OpenSSL default, verify with wolfProvider"
    
    # Sign data with OpenSSL default
    echo "Signing data with OpenSSL default..."
    openssl dgst -sha256 -sign "$key_file" \
        -provider default -passin pass: \
        -out "$openssl_sig_file" "$data_file"
    
    if [ ! -s "$openssl_sig_file" ]; then
        echo "[FAIL] RSA-${key_size} signing with OpenSSL default failed"
        exit 1
    fi
    
    # Verify signature with wolfProvider
    echo "Verifying signature with wolfProvider..."
    openssl dgst -sha256 -verify "$pub_key_file" \
        -provider-path $WOLFPROV_PATH -provider libwolfprov \
        -signature "$openssl_sig_file" "$data_file"
    
    if [ $? -eq 0 ]; then
        echo "[PASS] Interop: OpenSSL sign, wolfProvider verify successful"
    else
        echo "[FAIL] Interop: OpenSSL sign, wolfProvider verify failed"
        exit 1
    fi
}

for key_size in "${KEY_SIZES[@]}"; do
    echo -e "\n=== Testing RSA-${key_size} Key Generation ==="
    
    # Generate RSA key with wolfProvider
    echo "Generating RSA-${key_size} key with wolfProvider..."
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:${key_size} \
        -provider-path $WOLFPROV_PATH -provider libwolfprov \
        -out "rsa_outputs/rsa_wolf_${key_size}.pem" -pass pass:

    # Verify the key was generated
    if [ -s "rsa_outputs/rsa_wolf_${key_size}.pem" ]; then
        echo "[PASS] RSA-${key_size} key generation successful"
    else
        echo "[FAIL] RSA-${key_size} key generation failed"
        exit 1
    fi
    
    # Display key information
    echo "Key information:"
    openssl rsa -in "rsa_outputs/rsa_wolf_${key_size}.pem" -text -noout \
        -provider-path $WOLFPROV_PATH -provider libwolfprov
    
    # Validate key using default provider only
    validate_key "$key_size"
    
    # Test interoperability between wolfProvider and OpenSSL
    test_sign_verify_interop "$key_size"
done

echo -e "\n=== All RSA key generation and sign/verify tests completed successfully ==="
exit 0
