# Dockerfile for wolfProvider testing
# Supports: curl, nginx, grpc, ipmitool, net-snmp, openldap, openvpn, socat, sssd, stunnel
FROM debian:bookworm
# Install required dependencies
RUN apt-get update -y && apt-get install -y \
    autoconf \
    autoconf-archive \
    automake \
    autotools-dev \
    apache2-dev \
    bc \
    bison \
    build-essential \
    clang \
    curl \
    cmake \
    check \
    cpanminus \
    flex \
    git \
    libcap-dev \
    libcap-ng-dev \
    libc++-dev \
    libjansson-dev \
    libldb-dev \
    libldb2 \
    liblz4-dev \
    liblzo2-dev \
    libnl-genl-3-200 \
    libnl-genl-3-dev \
    libpam0g-dev \
    libperl-dev \
    libpcre3-dev \
    libpsl-dev \
    libpsl5 \
    libreadline-dev \
    libsystemd-dev \
    libfreeipmi-dev \
    libsasl2-dev \
    libssl-dev \
    libtool \
    libutf8proc-dev \
    libwrap0-dev \
    libcurl4-openssl-dev \
    libcjose-dev \
    libhiredis-dev \
    libmemcached-dev \
    linux-libc-dev \
    m4 \
    man2html \
    net-tools \
    nghttp2 \
    perl \
    pkg-config \
    python3 \
    python3-dev \
    python3-distutils \
    python3-docutils \
    python3-impacket \
    python3-ldb \
    sudo \
    wget \
    zlib1g-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Perl dependencies
RUN cpanm -n Proc::Find Net::SSLeay IO::Socket::SSL

# Create user with specific UID/GID
ARG HOST_UID=1001
ARG HOST_GID=1001
RUN groupadd -g ${HOST_GID} user && \
    useradd -u ${HOST_UID} -g ${HOST_GID} -m user

# Switch to user
USER user
WORKDIR /home/user
