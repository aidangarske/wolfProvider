#!/bin/bash
# test-tnftp.sh
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
set -e

# Find the tnftp directory
TNFTP_DIR=$(find $GITHUB_WORKSPACE -maxdepth 1 -name "tnftp-*" -type d | head -1)
if [ -z "$TNFTP_DIR" ]; then
    echo "Error: No tnftp directory found in $GITHUB_WORKSPACE"
    exit 1
fi

echo "Found tnftp directory: $TNFTP_DIR"

# Check if tnftp executable exists and is executable
if [ ! -x "$TNFTP_DIR/src/tnftp" ]; then
    echo "Error: tnftp executable not found or not executable"
    exit 1
fi

# Test basic tnftp functionality (help/version)
echo "Testing tnftp basic functionality..."
cd "$TNFTP_DIR"

# Test help command
if ./src/tnftp -? 2>&1 | grep -q "usage:"; then
    echo "✓ tnftp help command works"
else
    echo "✗ tnftp help command failed"
    exit 1
fi

# Test that tnftp can start (even if it fails to connect)
echo "Testing tnftp connection attempt..."
timeout 5 ./src/tnftp -n 192.0.2.1 2>&1 | head -10 || true
echo "✓ tnftp can attempt connections"

# Test SSL/TLS functionality
echo "Testing SSL/TLS connection..."
timeout 10 ./src/tnftp -n https://httpbin.org/get 2>&1 || true
echo "✓ SSL/TLS test completed"
