#!/bin/bash

#----tpm2-tools.sh----
#
# This script runs the tpm2-tools tests against the FIPS wolfProvider.
# Environment variables TPM2_TOOLS_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
TPM2_TOOLS_REF="5.7"

# Define base directories for cleaner paths
USER=$(whoami)
WOLFPROV_DIR="/home/$USER/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

cd "$WOLFPROV_DIR"

# Clone tpm2-tools repo
rm -rf tpm2-tools
git clone --depth=1 --branch="${TPM2_TOOLS_REF}" https://github.com/tpm2-software/tpm2-tools.git

cd tpm2-tools

# Configure tpm2-tools to use system OpenSSL and enable tests
./bootstrap
./configure \
  --prefix="$WOLFPROV_DIR/tpm2-tools-install" \
  --with-openssl="$OPENSSL_INSTALL" \
  --enable-unit \

# Build tpm2-tools
make -j$(nproc)

# Setup wolfProvider environment
echo "Setting up environment..."
# export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"

# Run only unit tests and integration tests that dont need TPM2 hardware/simulator
make check TESTS="test/unit/test_string_bytes test/unit/test_files \
test/unit/test_tpm2_header test/unit/test_tpm2_attr_util test/unit/test_tpm2_alg_util \
test/unit/test_pcr test/unit/test_tpm2_auth_util test/unit/test_tpm2_errata \
test/unit/test_tpm2_session test/unit/test_tpm2_policy test/unit/test_tpm2_util \
test/unit/test_options test/unit/test_cc_util test/unit/test_tpm2_eventlog \
test/unit/test_tpm2_eventlog_yaml test/unit/test_object \
test/integration/tests/X509certutil test/integration/tests/toggle_options \
test/integration/tests/rc_decode test/integration/tests/X509certutil"

if [ $? -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
