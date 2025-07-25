#!/bin/bash

#----libssh2.sh----
#
# This script runs the libssh2 tests against the FIPS wolfProvider.
# Environment variables LIBSSH2_REF, WOLFSSL_REF, and OPENSSL_REF
# are set by Jenkins.
set -e
set -x

# Use stable version instead of specific commit
LIBSSH2_REF="libssh2-1.10.0"

# Define base directories for cleaner paths
USER=$(whoami)
WOLFPROV_DIR="/home/${USER}/wolfProvider"
WOLFSSL_INSTALL="$WOLFPROV_DIR/wolfssl-install"
OPENSSL_INSTALL="$WOLFPROV_DIR/openssl-install"
WOLFPROV_INSTALL="$WOLFPROV_DIR/wolfprov-install"

# Go to wolfProvider directory
cd "$WOLFPROV_DIR"

# Set up locale to fix mansyntax.sh test
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# Clone libssh2 repo
# rm -rf libssh2
# git clone --depth=1 --branch="${LIBSSH2_REF}" https://github.com/libssh2/libssh2.git

# Build libssh2
cd libssh2

# Turn provider env ON for building/linking libssh2
export WOLFSSL_ISFIPS=1
export GITHUB_WORKSPACE="$WOLFPROV_DIR"
source "$WOLFPROV_DIR/scripts/env-setup"

# Build (optionally add rpath here)
autoreconf -fi
LDFLAGS="-Wl,-rpath,$OPENSSL_INSTALL/lib" \
CPPFLAGS="-I$OPENSSL_INSTALL/include" \
./configure --with-crypto=openssl --with-libssl-prefix="${OPENSSL_INSTALL}"
make -j"$(nproc)"

# Create sshd wrapper and export for the tests
cat > "$WOLFPROV_DIR/sshd-wrapper.sh" <<'EOF'
#!/bin/sh
exec env -i \
  PATH=/usr/sbin:/usr/bin:/bin \
  LC_ALL=C LANG=C \
  LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu \
  OPENSSL_CONF= \
  OPENSSL_MODULES= \
  PKG_CONFIG_PATH= \
  LDFLAGS= \
  CPPFLAGS= \
  /usr/sbin/sshd "$@"
EOF
chmod +x "$WOLFPROV_DIR/sshd-wrapper.sh"
export SSHD="$WOLFPROV_DIR/sshd-wrapper.sh"

# Run libssh2’s own test-suite
make check

# Now run your out-of-tree tests. Start sshd via wrapper (clean env) and run client with provider.
cd "$WOLFPROV_DIR/libssh2/tests"

$SSHD -f /dev/null -h "$PWD/etc/host" \
    -o 'Port 4711' \
    -o 'Protocol 2' \
    -o 'HostKeyAlgorithms ssh-rsa' \
    -o 'PubkeyAcceptedAlgorithms ssh-rsa' \
    -o 'KexAlgorithms diffie-hellman-group14-sha256' \
    -o 'ListenAddress 127.0.0.1' \
    -o "AuthorizedKeysFile $PWD/etc/user.pub" \
    -o 'UsePrivilegeSeparation no' \
    -o 'StrictModes no' \
    -D -e -d \
    $libssh2_sshd_params &
sshdpid=$!


trap "kill ${sshdpid}; echo signal killing sshd; exit 1;" EXIT
sleep 3

# Client side WITH provider env
(
  source "$WOLFPROV_DIR/scripts/env-setup"
  ./ssh2
)
ec=$?

kill "${sshdpid}" >/dev/null 2>&1 || true
trap - EXIT

if [ $ec -eq 0 ]; then
  echo "Workflow completed successfully"
else
  echo "Workflow failed"
  exit 1
fi
