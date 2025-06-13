# Dockerfile for wolfProvider testing
# Supports: curl, nginx, grpc, ipmitool, net-snmp, openldap, openvpn, socat, sssd, stunnel
FROM debian:bookworm

# Install required dependencies
RUN apt-get update -y && apt-get install -y \
    autoconf \
    autoconf-archive \
    automake \
    autotools-dev \
    bc \
    bind9utils \
    build-essential \
    clang \
    curl \
    cmake \
    cpanminus \
    dnsutils \
    gettext \
    gettext-base \
    autopoint \
    git \
    libc-ares-dev \
    libcap-dev \
    libcap-ng-dev \
    libc++-dev \
    libdhash-dev \
    libini-config-dev \
    libkrb5-dev \
    libldap2-dev \
    libldb-dev \
    libldb2 \
    liblz4-dev \
    liblzo2-dev \
    libnl-genl-3-200 \
    libnl-genl-3-dev \
    libpam0g-dev \
    libperl-dev \
    libpcre2-dev \
    libpcre3-dev \
    libpopt-dev \
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
    linux-libc-dev \
    m4 \
    man2html \
    nghttp2 \
    net-tools \
    perl \
    pkg-config \
    python3 \
    python3-dev \
    python3-distutils \
    python3-docutils \
    python3-impacket \
    python3-ldb \
    python3-pytest \
    python3-pytest-asyncio \
    python3-pytest-cov \
    python3-pytest-timeout \
    sudo \
    wget \
    zlib1g-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Python 3.13 from source
RUN cd /tmp && \
    wget https://www.python.org/ftp/python/3.13.0/Python-3.13.0.tgz && \
    tar xzf Python-3.13.0.tgz && \
    cd Python-3.13.0 && \
    ./configure --enable-optimizations && \
    make -j$(nproc) && \
    make altinstall && \
    cd .. && \
    rm -rf Python-3.13.0 Python-3.13.0.tgz

# Install Perl dependencies
RUN cpanm -n Proc::Find Net::SSLeay IO::Socket::SSL

# Create user with specific UID/GID
ARG HOST_UID
ARG HOST_GID
RUN groupadd -g ${HOST_GID} user && \
    useradd -u ${HOST_UID} -g ${HOST_GID} -m user && \
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create ldb.h symlink before switching to user
RUN mkdir -p /home/user/wolfProvider/samba-4.0 && \
    ln -sf /usr/include/samba-4.0/ldb.h /home/user/wolfProvider/samba-4.0/ldb.h && \
    ln -sf /usr/include/samba-4.0/ldb_errors.h /home/user/wolfProvider/samba-4.0/ldb_errors.h && \
    ln -sf /usr/include/samba-4.0/ldb_handlers.h /home/user/wolfProvider/samba-4.0/ldb_handlers.h && \
    ln -sf /usr/include/samba-4.0/ldb_module.h /home/user/wolfProvider/samba-4.0/ldb_module.h && \
    ln -sf /usr/include/samba-4.0/ldb_version.h /home/user/wolfProvider/samba-4.0/ldb_version.h && \
    ln -sf /usr/include/samba-4.0/ldb.h /usr/local/include/ldb.h && \
    ln -sf /usr/include/samba-4.0/ldb_errors.h /usr/local/include/ldb_errors.h && \
    ln -sf /usr/include/samba-4.0/ldb_handlers.h /usr/local/include/ldb_handlers.h && \
    ln -sf /usr/include/samba-4.0/ldb_module.h /usr/local/include/ldb_module.h && \
    ln -sf /usr/include/samba-4.0/ldb_version.h /usr/local/include/ldb_version.h

# Switch to user
USER user
WORKDIR /home/user
