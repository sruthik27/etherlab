FROM --platform=linux/amd64 public.ecr.aws/docker/library/debian:bookworm-slim

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    iproute2 \
    iputils-ping \
    net-tools \
    hostname \
    curl \
    ca-certificates \
    gnupg \
    binutils \
    xz-utils \
    python3 \
    libc6-i386 \
    libgcc-s1:i386 \
    libstdc++6:i386 \
    zlib1g:i386 && \
    rm -rf /var/lib/apt/lists/*

RUN printf '%s\n' 'deb [trusted=yes] https://netdevops.fury.site/apt/ /' \
    > /etc/apt/sources.list.d/netdevops.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends iouyap && \
    rm -rf /var/lib/apt/lists/*

# Older IOL binaries require libcrypto.so.4, which is no longer shipped in
# current Debian releases. Extract a compatible 32-bit libcrypto and pin a
# compatibility symlink for the IOS process.
RUN mkdir -p /compat && \
    cd /compat && \
    curl -fsSLO http://archive.debian.org/debian/pool/main/o/openssl/libssl1.0.0_1.0.1t-1+deb8u8_i386.deb && \
    ar x libssl1.0.0_1.0.1t-1+deb8u8_i386.deb && \
    mkdir -p root && \
    tar -xf data.tar.xz -C root && \
    ln -sf /compat/root/usr/lib/i386-linux-gnu/libcrypto.so.1.0.0 /compat/root/usr/lib/i386-linux-gnu/libcrypto.so.4

COPY build/cisco_iol/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /iol
COPY local/images/cisco_iol-L2-15.1a.bin /iol/iol.bin
COPY build/cisco_iol/keygen.py /iol/keygen.py
RUN chmod +x /iol/keygen.py
RUN chmod +x /iol/iol.bin

ENTRYPOINT ["/entrypoint.sh"]
