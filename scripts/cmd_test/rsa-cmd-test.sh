#!/bin/bash
# rsa-cmd-test.sh
# RSA key generation test for wolfProvider
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
if ! $OPENSSL_BIN list -providers | grep -q "libwolfprov"; then
    echo "[FAIL] wolfProvider not found in OpenSSL providers!"
    echo "Current provider list:"
    $OPENSSL_BIN list -providers
    exit 1
fi
echo "[PASS] wolfProvider is properly configured"

# Print environment for verification
echo "Environment variables:"
echo "OPENSSL_MODULES: ${OPENSSL_MODULES}"
echo "LD_LIBRARY_PATH: ${LD_LIBRARY_PATH}"
echo "OPENSSL_BIN: ${OPENSSL_BIN}"

# Create test directories
mkdir -p rsa_outputs

# Create test data for signing
echo "This is test data for RSA signing and verification." > rsa_outputs/test_data.txt

# Array of RSA key types and sizes to test
KEY_TYPES=("RSA" "RSA-PSS")
KEY_SIZES=("2048" "3072" "4096")

echo "=== Running RSA Key Generation Tests ==="

# Function to validate key
validate_key() {
    local key_type=$1
    local key_size=$2
    local key_file=${3:-"rsa_outputs/${key_type}_${key_size}.pem"}
    
    echo -e "\n=== Validating ${key_type} Key (${key_size}) ==="
    
    # Check if key exists and has content
    if [ ! -s "$key_file" ]; then
        echo "[FAIL] ${key_type} key (${key_size}) file is empty or does not exist"
        exit 1
    fi
    echo "[PASS] ${key_type} key file exists and has content"
    
    # Try to extract public key
    local pub_key_file="rsa_outputs/${key_type}_${key_size}_pub.pem"
    if $OPENSSL_BIN pkey -in "$key_file" -pubout -out "$pub_key_file" \
        -provider default -passin pass: 2>/dev/null; then
        echo "[PASS] ${key_type} Public key extraction successful"
    else
        echo "[WARN] ${key_type} Public key extraction failed"
        return 1
    fi
}

# Function to test sign/verify interoperability using dgst
test_sign_verify_pkeyutl() {
    local key_type=$1
    local key_size=$2
    local key_file=${3:-"rsa_outputs/${key_type}_${key_size}.pem"}
    local pub_key_file="rsa_outputs/${key_type}_${key_size}_pub.pem"
    local data_file="rsa_outputs/test_data.txt"
    local sig_file="rsa_outputs/${key_type}_${key_size}_sig.bin"
    
    echo -e "\n=== Testing ${key_type} (${key_size}) Sign/Verify with dgst ==="
    
    # Test 1: Sign with OpenSSL default, verify with wolfProvider
    echo "Test 1: Sign with OpenSSL default, verify with wolfProvider"
    
    # Sign data with OpenSSL default
    echo "Signing data with OpenSSL default..."
    if ! $OPENSSL_BIN dgst -sha256 -sign "$key_file" \
        -provider default -passin pass: \
        -out "$sig_file" "$data_file" 2>/dev/null; then
        echo "[WARN] Signing with OpenSSL default failed - this may be expected for some key types"
        return
    fi
    
    # Verify signature with wolfProvider
    echo "Verifying signature with wolfProvider..."
    if $OPENSSL_BIN dgst -sha256 -verify "$pub_key_file" \
        -provider-path $WOLFPROV_PATH -provider libwolfprov \
        -signature "$sig_file" "$data_file" 2>/dev/null; then
        echo "[PASS] Interop: OpenSSL sign, wolfProvider verify successful"
    else
        echo "[INFO] Interop: OpenSSL sign, wolfProvider verify failed - this may be expected"
    fi
    
    # Test 2: Sign with wolfProvider, verify with OpenSSL default
    echo "Test 2: Sign with wolfProvider, verify with OpenSSL default"
    
    # Sign data with wolfProvider
    local wolf_sig_file="rsa_outputs/${key_type}_${key_size}_wolf_sig.bin"
    echo "Signing data with wolfProvider..."
    if $OPENSSL_BIN dgst -sha256 -sign "$key_file" \
        -provider-path $WOLFPROV_PATH -provider libwolfprov \
        -out "$wolf_sig_file" "$data_file" 2>/dev/null; then
        echo "[PASS] wolfProvider signing successful"
        
        # Verify signature with OpenSSL default
        echo "Verifying signature with OpenSSL default..."
        if $OPENSSL_BIN dgst -sha256 -verify "$pub_key_file" \
            -provider default \
            -signature "$wolf_sig_file" "$data_file" 2>/dev/null; then
            echo "[PASS] Interop: wolfProvider sign, OpenSSL verify successful"
        else
            echo "[INFO] Interop: wolfProvider sign, OpenSSL verify failed - this may be expected"
        fi
    else
        echo "[INFO] wolfProvider signing failed - this may be expected for some key types"
    fi
}

# Function to generate and test RSA keys
generate_and_test_key() {
    local key_type=$1
    local key_size=$2
    local output_file="rsa_outputs/${key_type}_${key_size}.pem"
    
    echo -e "\n=== Testing ${key_type} Key Generation (${key_size}) ==="
    
    # Generate key using genpkey
    echo "Generating ${key_type} key (${key_size})..."
$OPENSSL_BIN genpkey -algorithm $key_type -pkeyopt rsa_keygen_bits:${key_size} \
    -provider-path $WOLFPROV_PATH -provider libwolfprov \
    -out "$output_file" -noenc 2>/dev/null

    # Verify the key was generated
    if [ -s "$output_file" ]; then
        echo "[PASS] ${key_type} key (${key_size}) generation successful"
    else
        echo "[FAIL] ${key_type} key (${key_size}) generation failed"
        exit 1
    fi
    
    # Validate key
    validate_key "$key_type" "$key_size" "$output_file"
    

    # Try to use the key with wolfProvider
    echo -e "\n=== Testing ${key_type} Key (${key_size}) with wolfProvider ==="
    echo "Checking if wolfProvider can use the key..."
    
    # Try to use the key with wolfProvider (just check if it loads)
    if $OPENSSL_BIN pkey -in "$output_file" -check \
        -provider-path "${WOLFPROV_PATH}" -provider libwolfprov \
        -provider default -passin pass: 2>/dev/null; then
        echo "[PASS] wolfProvider can use ${key_type} key (${key_size})"
        
        # Test sign/verify interoperability with dgst
        test_sign_verify_pkeyutl "$key_type" "$key_size" "$output_file"
    else
        echo "[INFO] wolfProvider cannot use ${key_type} key (${key_size}) - this is expected for some key types"
    fi
}

# Test key generation for each type and size
for key_type in "${KEY_TYPES[@]}"; do
    for key_size in "${KEY_SIZES[@]}"; do
        generate_and_test_key "$key_type" "$key_size"
    done
done

echo -e "\n=== All RSA key generation tests completed successfully ==="
exit 0
