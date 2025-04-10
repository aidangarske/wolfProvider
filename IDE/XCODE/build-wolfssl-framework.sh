#!/bin/bash

# build-wolfssl-framework.sh
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
# along with wolfProvider. If not, see <http://www.gnu.org/licenses/>.

set -euo pipefail

WOLFSSL_DIR=$(pwd)
OUTDIR=$(pwd)/artifacts
LIPODIR=${OUTDIR}/lib
SDK_OUTPUT_DIR=${OUTDIR}/xcframework

CFLAGS_COMMON=""
CPPFLAGS_COMMON=""
# Base configure flags
CONF_OPTS="--disable-shared --enable-static --enable-armasm=no"

helpFunction()
{
   echo ""
   echo "Usage: $0 [-c <config flags>]"
   echo -e "\t-c Extra flags to be passed to ./configure"
   exit 1 # Exit script after printing help
}

# Parse command line arguments
while getopts ":c:p:" opt; do
  case $opt in
    c)
      CONF_OPTS+=" $OPTARG"
      ;;
    p)
      CPPFLAGS_COMMON+=" $OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2; helpFunction
      ;;
  esac
done

mkdir -p $LIPODIR
mkdir -p $SDK_OUTPUT_DIR
cd $WOLFSSL_DIR && ./autogen.sh

build() { # <ARCH=arm64|x86_64> <TYPE=iphonesimulator|iphoneos|macosx|watchos|watchsimulator|appletvos|appletvsimulator>
    set -x
    pushd .
    cd $WOLFSSL_DIR

    ARCH=$1
    HOST="${ARCH}-apple-darwin"
    TYPE=$2
    SDK_ROOT=$(xcrun --sdk ${TYPE} --show-sdk-path)

    ./configure -prefix=${OUTDIR}/wolfssl-install-${TYPE}-${ARCH} ${CONF_OPTS} --host=${HOST} \
        CFLAGS="${CFLAGS_COMMON} -arch ${ARCH} -isysroot ${SDK_ROOT}" CPPFLAGS="${CPPFLAGS_COMMON}"
    make
    make install

    popd
    set +x
}

XCFRAMEWORKS=
for type in iphonesimulator macosx ; do
    build arm64 ${type}
    build x86_64 ${type}

    # Create universal binaries from architecture-specific static libraries
    lipo \
        "$OUTDIR/wolfssl-install-${type}-x86_64/lib/libwolfssl.a" \
        "$OUTDIR/wolfssl-install-${type}-arm64/lib/libwolfssl.a" \
        -create -output $LIPODIR/libwolfssl-${type}.a

    echo "Checking libraries"
    xcrun -sdk ${type} lipo -info $LIPODIR/libwolfssl-${type}.a
    XCFRAMEWORKS+=" -library ${LIPODIR}/libwolfssl-${type}.a -headers ${OUTDIR}/wolfssl-install-${type}-arm64/include"
done

for type in iphoneos ; do
    build arm64 ${type}

    # Create universal binaries from architecture-specific static libraries
    lipo \
        "$OUTDIR/wolfssl-install-${type}-arm64/lib/libwolfssl.a" \
        -create -output $LIPODIR/libwolfssl-${type}.a

    echo "Checking libraries"
    xcrun -sdk ${type} lipo -info $LIPODIR/libwolfssl-${type}.a
    XCFRAMEWORKS+=" -library ${LIPODIR}/libwolfssl-${type}.a -headers ${OUTDIR}/wolfssl-install-${type}-arm64/include"
done

############################################################################################################################################
#  ********** BUILD FRAMEWORK
############################################################################################################################################

xcodebuild -create-xcframework ${XCFRAMEWORKS} -output ${SDK_OUTPUT_DIR}/libwolfssl.xcframework
