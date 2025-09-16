FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wget ca-certificates xorriso isolinux whois cpio && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY build-iso.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/build-iso.sh
RUN mkdir -p /out
COPY preseed.cfg /out/

ENTRYPOINT ["/usr/local/bin/build-iso.sh"]