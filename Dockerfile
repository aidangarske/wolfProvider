# Dockerfile for wolfProvider Jenkins testing
FROM debian:bookworm
# Install required dependencies
RUN apt-get update -y && apt-get install -y \
    acl \
    attr \
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
    openssl \
    cmake \
    check \
    cpanminus \
    expect \
    flex \
    gawk \
    gperf \
    git \
    gengetopt \
    gettext \
    gnupg \
    help2man \
    iproute2 \
    libacl1-dev \
    libattr1-dev \
    libargon2-dev \
    libavahi-client-dev \
    libavahi-compat-libdnssd-dev \
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
    libpcre2-dev \
    libpsl-dev \
    libpsl5 \
    libdevmapper-dev \
    libreadline-dev \
    libsystemd-dev \
    libseccomp-dev \
    libfreeipmi-dev \
    libsasl2-dev \
    libtool \
    libtool-bin \
    libutf8proc-dev \
    libwrap0-dev \
    libcurl4-openssl-dev \
    libcunit1-dev \
    libudev-dev \
    libcbor-dev \
    libpcsclite-dev \
    libcmocka-dev \
    libcjose-dev \
    libeac3 \
    libjson-c-dev \
    libhiredis-dev \
    libltdl7 \
    libltdl-dev \
    libmemcached-dev \
    libmount-dev \
    libusb-1.0-0-dev \
    libuv1-dev \
    libidn2-dev \
    libtss2-dev \
    libvncserver-dev \
    libx11-dev \
    libxdamage-dev \
    libxext-dev \
    libxfixes-dev \
    libxi-dev \
    libxml2-dev \
    libxinerama-dev \
    libxrandr-dev \
    libxss-dev \
    libxtst-dev \
    libxxhash-dev \
    libzstd-dev \
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
    pps-tools \
    psmisc \
    python3 \
    python3-cmarkgfm \
    python3-dev \
    python3-distutils \
    python3-docutils \
    python3-impacket \
    python3-ldb \
    python3-pytest \
    python-dev-is-python3 \
    scep \
    softhsm2 \
    swtpm \
    ssh \
    sudo \
    systemd \
    tigervnc-viewer \
    tpm2-abrmd \
    tpm2-tools \
    uuid-dev \
    vim \
    wget \
    x11proto-core-dev \
    xvfb \
    zlib1g-dev \
    zlib1g \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create user with specific UID/GID (for compatibility if needed)
ARG HOST_UID=1001
ARG HOST_GID=1001
RUN groupadd -g ${HOST_GID} user && \
    useradd -u ${HOST_UID} -g ${HOST_GID} -m user

# Configure sudo for the user (no password required)
RUN usermod -aG sudo user && \
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Keep running as root for full permissions
# USER user
WORKDIR /home/user