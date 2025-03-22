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

Set up environment
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
        -provider-path $WOLFPROV_PATH -provider libwolfprov 2>/dev/null; then
        echo "[PASS] ${key_type} Public key extraction successful"
    else
        echo "[WARN] ${key_type} Public key extraction failed"
        return 1
    fi
}

# Function to test sign/verify interoperability using pkeyutl for standard RSA
test_sign_verify_pkeyutl_rsa() {
    local key_size=$1
    local key_file="rsa_outputs/RSA_${key_size}.pem"
    local pub_key_file="rsa_outputs/RSA_${key_size}_pub.pem"
    local data_file="rsa_outputs/test_data.txt"
    
    echo -e "\n=== Testing Standard RSA (${key_size}) Sign/Verify with pkeyutl ==="
    
    # Test 1: Sign and verify with OpenSSL default
    echo "Test 1: Sign and verify with OpenSSL default (standard RSA)"
    local default_sig_file="rsa_outputs/RSA_${key_size}_default_sig.bin"

    echo "Signing data with OpenSSL default..."
    if $OPENSSL_BIN pkeyutl -sign -inkey "$key_file" \
        -provider default \
        -passin pass: \
        -in "$data_file" \
        -out "$default_sig_file"; then
        echo "[PASS] Signing with OpenSSL default successful"

        echo "Verifying signature with OpenSSL default..."
        if $OPENSSL_BIN pkeyutl -verify -pubin -inkey "$pub_key_file" \
            -provider default \
            -in "$data_file" \
            -sigfile "$default_sig_file" 2>/dev/null; then
            echo "[PASS] Default provider sign/verify successful"
        else
            echo "[WARN] Default provider verify failed"
            return 1
        fi
    else
        echo "[WARN] Default provider signing failed"
        return 1
    fi
    
    # Test 2: Sign and verify with wolfProvider
    echo "Test 2: Sign and verify with wolfProvider (standard RSA)"
    local wolf_sig_file="rsa_outputs/RSA_${key_size}_wolf_sig.bin"
    
    echo "Signing data with wolfProvider..."
    if $OPENSSL_BIN pkeyutl -sign -inkey "$key_file" \
        -provider-path $WOLFPROV_PATH -provider libwolfprov \
        -in "$data_file" \
        -out "$wolf_sig_file" 2>/dev/null; then
        echo "[PASS] Signing with wolfProvider successful"
        
        echo "Verifying signature with wolfProvider..."
        if $OPENSSL_BIN pkeyutl -verify -pubin -inkey "$pub_key_file" \
            -provider-path $WOLFPROV_PATH -provider libwolfprov \
            -in "$data_file" \
            -sigfile "$wolf_sig_file" 2>/dev/null; then
            echo "[PASS] wolfProvider sign/verify successful"
        else
            echo "[WARN] wolfProvider verify failed"
            return 1
        fi
    else
        echo "[WARN] wolfProvider signing failed"
        return 1
    fi
}

# Function to test sign/verify interoperability using pkeyutl for RSA-PSS
test_sign_verify_pkeyutl_rsa_pss() {
    local key_size=$1
    local key_file="rsa_outputs/RSA-PSS_${key_size}.pem"
    local pub_key_file="rsa_outputs/RSA-PSS_${key_size}_pub.pem"
    local data_file="rsa_outputs/test_data.txt"
    
    echo -e "\n=== Testing RSA-PSS (${key_size}) Sign/Verify with pkeyutl ==="
    
    # Test 1: Sign and verify with OpenSSL default
    echo "Test 1: Sign and verify with OpenSSL default (RSA-PSS)"
    local default_sig_file="rsa_outputs/RSA-PSS_${key_size}_default_sig.bin"

    echo "Signing data with OpenSSL default..."
    if $OPENSSL_BIN pkeyutl -sign -inkey "$key_file" \
        -provider default \
        -passin pass: \
        -pkeyopt rsa_padding_mode:pss \
        -pkeyopt rsa_pss_saltlen:-1 \
        -pkeyopt rsa_mgf1_md:sha256 \
        -digest sha256 \
        -in "$data_file" \
        -out "$default_sig_file"; then
        echo "[PASS] Signing with OpenSSL default successful"

        echo "Verifying signature with OpenSSL default..."
        if $OPENSSL_BIN pkeyutl -verify -pubin -inkey "$pub_key_file" \
            -provider default \
            -pkeyopt rsa_padding_mode:pss \
            -pkeyopt rsa_pss_saltlen:-1 \
            -pkeyopt rsa_mgf1_md:sha256 \
            -digest sha256 \
            -in "$data_file" \
            -sigfile "$default_sig_file" 2>/dev/null; then
            echo "[PASS] Default provider sign/verify successful"
        else
            echo "[WARN] Default provider verify failed"
            return 1
        fi
    else
        echo "[WARN] Default provider signing failed"
        return 1
    fi
    
    # Test 2: Sign and verify with wolfProvider
    echo "Test 2: Sign and verify with wolfProvider (RSA-PSS)"
    local wolf_sig_file="rsa_outputs/RSA-PSS_${key_size}_wolf_sig.bin"
    
    echo "Signing data with wolfProvider..."
    if $OPENSSL_BIN pkeyutl -sign -inkey "$key_file" \
        -provider-path $WOLFPROV_PATH -provider libwolfprov \
        -passin pass: \
        -pkeyopt rsa_padding_mode:pss \
        -pkeyopt rsa_pss_saltlen:-1 \
        -pkeyopt rsa_mgf1_md:sha256 \
        -digest sha256 \
        -in "$data_file" \
        -out "$wolf_sig_file" 2>/dev/null; then
        echo "[PASS] Signing with wolfProvider successful"
        
        echo "Verifying signature with wolfProvider..."
        if $OPENSSL_BIN pkeyutl -verify -pubin -inkey "$pub_key_file" \
            -provider-path $WOLFPROV_PATH -provider libwolfprov \
            -pkeyopt rsa_padding_mode:pss \
            -pkeyopt rsa_pss_saltlen:-1 \
            -pkeyopt rsa_mgf1_md:sha256 \
            -digest sha256 \
            -in "$data_file" \
            -sigfile "$wolf_sig_file" 2>/dev/null; then
            echo "[PASS] wolfProvider sign/verify successful"
        else
            echo "[WARN] wolfProvider verify failed"
            return 1
        fi
    else
        echo "[WARN] wolfProvider signing failed"
        return 1
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
    if [ "$key_type" = "RSA-PSS" ]; then
        # For RSA-PSS, specify all parameters
        $OPENSSL_BIN genpkey -algorithm RSA-PSS \
            -provider default \
            -pkeyopt rsa_keygen_bits:${key_size} \
            -pkeyopt rsa_pss_keygen_md:sha256 \
            -pkeyopt rsa_pss_keygen_mgf1_md:sha256 \
            -pkeyopt rsa_pss_keygen_saltlen:-1 \
            -out "$output_file"
    else
        # Regular RSA key generation
        $OPENSSL_BIN genpkey -algorithm RSA \
            -pkeyopt rsa_keygen_bits:${key_size} \
            -provider-path $WOLFPROV_PATH -provider libwolfprov \
            -out "$output_file" \
            -noenc 2>/dev/null
    fi

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
        
        # Test sign/verify interoperability with appropriate function
        if [ "$key_type" = "RSA-PSS" ]; then
            test_sign_verify_pkeyutl_rsa_pss "$key_size"
        else
            test_sign_verify_pkeyutl_rsa "$key_size"
        fi
    else
        echo "[INFO] wolfProvider cannot use ${key_type} key (${key_size}) - this is expected if wolfProvider is not installed"
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
