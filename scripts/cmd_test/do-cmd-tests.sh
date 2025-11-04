#!/bin/bash
# do-cmd-tests.sh
# Run all command-line tests for wolfProvider
#
# Copyright (C) 2006-2025 wolfSSL Inc.
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
# along with wolfProvider. If not, see <http://www.gnu.org/licenses/>.

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd )"
UTILS_DIR="${REPO_ROOT}/scripts"

# Parse command-line arguments
RUN_HASH=0
RUN_AES=0
RUN_RSA=0
RUN_ECC=0
RUN_REQ=0
RUN_ALL=1

show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [TESTS]

Run wolfProvider command-line tests with optional configuration flags.

OPTIONS:
    --fips              Enable FIPS mode (sets WOLFSSL_ISFIPS=1)
    --replace-default   Indicate that wolfProvider is configured as replace-default
                        (requires --debian to be specified)
    --force-fail        Enable force-fail mode (sets WOLFPROV_FORCE_FAIL=1)
    --debian            Specify if using Debian packages (required with --replace-default)
    --help              Show this help message

TESTS (if none specified, all tests run):
    hash                Run hash comparison test
    aes                 Run AES comparison test
    rsa                 Run RSA key generation test
    ecc                 Run ECC key generation test
    req                 Run certificate request test

EXAMPLES:
    $0                                      # Run all tests
    $0 --fips                               # Run all tests in FIPS mode
    $0 --debian --replace-default rsa ecc   # Run RSA and ECC tests with replace-default
    $0 --fips --force-fail hash             # Run hash test in FIPS mode with force-fail

ENVIRONMENT VARIABLES:
    OPENSSL_BIN         Path to OpenSSL binary (auto-detected if not set)
    WOLFPROV_PATH       Path to wolfProvider modules directory
    WOLFPROV_CONFIG     Path to wolfProvider config file
    WOLFSSL_ISFIPS      Set to 1 for FIPS mode (or use --fips flag)
    WOLFPROV_FORCE_FAIL Set to 1 for force-fail mode (or use --force-fail flag)

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --fips)
            export WOLFSSL_ISFIPS=1
            shift
            ;;
        --replace-default)
            export WOLFPROV_REPLACE_DEFAULT=1
            shift
            ;;
        --force-fail)
            export WOLFPROV_FORCE_FAIL=1
            shift
            ;;
        --debian)
            export WOLFPROV_DEBIAN=1
            shift
            ;;
        --help|-h)
            show_help
            ;;
        hash)
            RUN_HASH=1
            RUN_ALL=0
            shift
            ;;
        aes)
            RUN_AES=1
            RUN_ALL=0
            shift
            ;;
        rsa)
            RUN_RSA=1
            RUN_ALL=0
            shift
            ;;
        ecc)
            RUN_ECC=1
            RUN_ALL=0
            shift
            ;;
        req)
            RUN_REQ=1
            RUN_ALL=0
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate that --debian is specified when --replace-default is used
if [ "${WOLFPROV_REPLACE_DEFAULT:-0}" = "1" ] && [ "${WOLFPROV_DEBIAN:-0}" != "1" ]; then
    echo "ERROR: --replace-default requires --debian to be specified"
    echo "Replace-default mode is only available with Debian packages"
    echo "Use --help for usage information"
    exit 1
fi

# If no specific tests were requested, run all tests
if [ $RUN_ALL -eq 1 ]; then
    RUN_HASH=1
    RUN_AES=1
    RUN_RSA=1
    RUN_ECC=1
    RUN_REQ=1
fi

source "${SCRIPT_DIR}/cmd-test-common.sh"

# If OPENSSL_BIN is not set, assume we are using a local build
if [ -z "${OPENSSL_BIN:-}" ]; then
    # Check if the install directories exist
    if [ ! -d "${REPO_ROOT}/openssl-install" ] || 
       [ ! -d "${REPO_ROOT}/wolfssl-install" ]; then
        echo "[FAIL] OpenSSL or wolfSSL install directories not found"
        echo "Please set OPENSSL_BIN or run build-wolfprovider.sh first"
        exit 1
    fi

    # Setup the environment for a local build
    source "${REPO_ROOT}/scripts/env-setup"
else
    # We are using a user-provided OpenSSL binary, manually set the test
    # environment variables rather than using env-setup.
    # Find the location of the wolfProvider modules
    if [ -z "${WOLFPROV_PATH:-}" ]; then
        export WOLFPROV_PATH=$(find /usr/lib /usr/local/lib -type d -name ossl-modules 2>/dev/null | head -n 1)
    fi
    # Set the path to the wolfProvider config file
    if [ -z "${WOLFPROV_CONFIG:-}" ]; then
        if [ "${WOLFSSL_ISFIPS:-0}" = "1" ]; then
            export WOLFPROV_CONFIG="${REPO_ROOT}/provider-fips.conf"
        else
            export WOLFPROV_CONFIG="${REPO_ROOT}/provider.conf"
        fi  
    fi
fi

echo "=== Running wolfProvider Command-Line Tests ==="
echo "Using OPENSSL_BIN: ${OPENSSL_BIN}" 
echo "Using WOLFPROV_PATH: ${WOLFPROV_PATH}"
echo "Using WOLFPROV_CONFIG: ${WOLFPROV_CONFIG}"
if [ "${WOLFSSL_ISFIPS}" = "1" ]; then
    echo "FIPS mode: ENABLED"
fi
if [ "${WOLFPROV_FORCE_FAIL}" = "1" ]; then
    echo "Force-fail mode: ENABLED"
fi
if [ "${WOLFPROV_REPLACE_DEFAULT}" = "1" ]; then
    echo "Replace-default mode: ENABLED"
fi

# Ensure we can switch providers before proceeding
use_default_provider
use_wolf_provider

# Initialize result variables
HASH_RESULT=0
AES_RESULT=0
RSA_RESULT=0
ECC_RESULT=0
REQ_RESULT=0

# Run the hash comparison test
if [ $RUN_HASH -eq 1 ]; then
    echo -e "\n=== Running Hash Comparison Test ==="
    "${REPO_ROOT}/scripts/cmd_test/hash-cmd-test.sh"
    HASH_RESULT=$?
fi

# Run the AES comparison test
if [ $RUN_AES -eq 1 ]; then
    echo -e "\n=== Running AES Comparison Test ==="
    "${REPO_ROOT}/scripts/cmd_test/aes-cmd-test.sh"
    AES_RESULT=$?
fi

# Run the RSA key generation test
if [ $RUN_RSA -eq 1 ]; then
    echo -e "\n=== Running RSA Key Generation Test ==="
    "${REPO_ROOT}/scripts/cmd_test/rsa-cmd-test.sh"
    RSA_RESULT=$?
fi

# Run the ECC key generation test
if [ $RUN_ECC -eq 1 ]; then
    echo -e "\n=== Running ECC Key Generation Test ==="
    "${REPO_ROOT}/scripts/cmd_test/ecc-cmd-test.sh"
    ECC_RESULT=$?
fi

# Run the Certificate Request test
if [ $RUN_REQ -eq 1 ]; then
    echo -e "\n=== Running Certificate Request Test ==="
    "${REPO_ROOT}/scripts/cmd_test/req-cmd-test.sh"
    REQ_RESULT=$?
fi

# Check results
ALL_PASSED=1
if [ $RUN_HASH -eq 1 ] && [ $HASH_RESULT -ne 0 ]; then
    ALL_PASSED=0
fi
if [ $RUN_AES -eq 1 ] && [ $AES_RESULT -ne 0 ]; then
    ALL_PASSED=0
fi
if [ $RUN_RSA -eq 1 ] && [ $RSA_RESULT -ne 0 ]; then
    ALL_PASSED=0
fi
if [ $RUN_ECC -eq 1 ] && [ $ECC_RESULT -ne 0 ]; then
    ALL_PASSED=0
fi
if [ $RUN_REQ -eq 1 ] && [ $REQ_RESULT -ne 0 ]; then
    ALL_PASSED=0
fi

if [ $ALL_PASSED -eq 1 ]; then
    echo -e "\n=== All Command-Line Tests Passed ==="
else
    echo -e "\n=== Command-Line Tests Failed ==="
fi

# Print configuration
if [ "${WOLFPROV_FORCE_FAIL}" = "1" ]; then
    echo "Force fail mode was enabled"
fi
if [ "${WOLFSSL_ISFIPS}" = "1" ]; then
    echo "FIPS mode was enabled"
fi
if [ "${WOLFPROV_REPLACE_DEFAULT}" = "1" ]; then
    echo "Replace-default mode was enabled"
fi

# Print test results (only for tests that were run)
echo ""
if [ $RUN_HASH -eq 1 ]; then
    echo "Hash Test Result: $HASH_RESULT (0=success)"
fi
if [ $RUN_AES -eq 1 ]; then
    echo "AES Test Result: $AES_RESULT (0=success)"
fi
if [ $RUN_RSA -eq 1 ]; then
    echo "RSA Test Result: $RSA_RESULT (0=success)"
fi
if [ $RUN_ECC -eq 1 ]; then
    echo "ECC Test Result: $ECC_RESULT (0=success)"
fi
if [ $RUN_REQ -eq 1 ]; then
    echo "REQ Test Result: $REQ_RESULT (0=success)"
fi

exit $((1 - ALL_PASSED))
