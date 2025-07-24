# Dockerfile for wolfProvider Jenkins testing
FROM debian:bookworm
# Install required dependencies
RUN apt-get update -y && apt-get install -y \
    acl \
    autoconf \
    autoconf-archive \
    automake \
    autotools-dev \
    asciidoctor \
    apache2-dev \
    bc \
    bison \
    build-essential \
    clang \
    curl \
    cmake \
    check \
    cpanminus \
    expect \
    flex \
    gperf \
    git \
    gettext \
    gnupg \
    iproute2 \
    libargon2-dev \
    libavahi-client-dev \
    linux-headers-generic \
    libc6 \
    libc6-dev \
    libcap2 \
    libcap-dev \
    libcap-ng-dev \
    libc++-dev \
    libjansson-dev \
    libjpeg62-turbo-dev \
    libldb-dev \
    libldb2 \
    liblz4-dev \
    liblzo2-dev \
    libblkid-dev \
    libnl-genl-3-200 \
    libnl-genl-3-dev \
    libnghttp2-dev \
    libnss3-dev \
    libpam0g-dev \
    libperl-dev \
    libpopt-dev \
    libpcre3-dev \
    libpsl-dev \
    libpsl5 \
    libdevmapper-dev \
    libreadline-dev \
    libsystemd-dev \
    libfreeipmi-dev \
    libsasl2-dev \
    libssh-dev \
    libtool \
    libutf8proc-dev \
    libwrap0-dev \
    libcurl4-openssl-dev \
    libcunit1-dev \
    libudev-dev \
    libcbor-dev \
    libpcsclite-dev \
    libcmocka-dev \
    libcjose-dev \
    libjson-c-dev \
    libhiredis-dev \
    libmemcached-dev \
    libmount-dev \
    libusb-1.0-0-dev \
    libuv1-dev \
    libvncserver-dev \
    libx11-dev \
    libxdamage-dev \
    libxext-dev \
    libxfixes-dev \
    libxi-dev \
    libxinerama-dev \
    libxrandr-dev \
    libxss-dev \
    libxtst-dev \
    linux-libc-dev \
    m4 \
    man2html \
    memcached \
    meson \
    net-tools \
    nghttp2 \
    ninja-build \
    opensc \
    pcsc-tools \
    pcscd \
    perl \
    pkgconf \
    pkg-config \
    psmisc \
    python3 \
    python3-dev \
    python3-distutils \
    python3-docutils \
    python3-impacket \
    python3-ldb \
    python3-pytest \
    softhsm2 \
    ssh \
    scdoc \
    sudo \
    systemd \
    tigervnc-viewer \
    uuid-dev \
    vim \
    wget \
    x11proto-core-dev \
    xvfb \
    zlib1g-dev \
    zlib1g \
    ninja-build \
    libpcre2-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Always upgrade GLIBC to support pre-built OpenSSL binaries (built with GLIBC 2.38+)
RUN echo "deb http://deb.debian.org/debian trixie main" >> /etc/apt/sources.list && \
    apt-get update -y && \
    apt-get install -y -t trixie libc6 libc6-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

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
