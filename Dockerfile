FROM ubuntu:20.04 as builder

ENV HAPROXY_VERSION 2.6.2
ENV HAPROXY_URL https://www.haproxy.org/download/2.6/src/haproxy-2.6.2.tar.gz
ENV HAPROXY_SHA256 f9b7dc06e02eb13b5d94dc66e0864a714aee2af9dfab10fa353ff9f1f52c8202
# Start haproxy build. See:
# https://github.com/docker-library/haproxy/blob/master/2.4/Dockerfile
RUN set -eux && apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
	gcc \
	libc6-dev \
	liblua5.3-dev \
	libpcre2-dev \
	libssl-dev \
	make && \
	rm -rf /var/lib/apt/lists/*; \
	curl -sL -o haproxy.tar.gz "$HAPROXY_URL"; \
	echo "$HAPROXY_SHA256 *haproxy.tar.gz" | sha256sum -c; \
	mkdir -p /usr/src/haproxy; \
	tar -xzf haproxy.tar.gz -C /usr/src/haproxy --strip-components=1; \
	rm haproxy.tar.gz; \
	makeOpts=' \
	TARGET=linux-glibc \
	USE_GETADDRINFO=1 \
	USE_LUA=1 LUA_INC=/usr/include/lua5.3 \
	USE_OPENSSL=1 \
	USE_PCRE2=1 USE_PCRE2_JIT=1 \
	USE_PROMEX=1 \
	\
	EXTRA_OBJS=" \
	" \
	'; \
	nproc="$(nproc)"; \
	eval "make -C /usr/src/haproxy -j '$nproc' all $makeOpts"; \
	eval "make -C /usr/src/haproxy install-bin $makeOpts"; \
	haproxy -v
# End haproxy build.

FROM ubuntu:20.04
LABEL org.opencontainers.image.authors="WBX3 apps team"

ENV LANG "C.UTF-8"

RUN set -eux && \
    apt-get update -y && \
    apt-get upgrade -y && \
    \
    apt-get install -y --no-install-recommends \
        bc \
        ca-certificates \
        curl \
        gawk \
        jq \
        liblua5.3-0 \
        libp11-kit0 \
        procps \
        socat && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists

# Pull in go template
RUN curl -Lo gucci https://github.com/noqcks/gucci/releases/download/1.5.5/gucci-v1.5.5-linux-amd64&&\
	echo "8177c796e3a4dc79c3f88b8571bb32f7a6ccf89be3c0b8a344ffa4067d4b28a5 gucci" | sha256sum -c && \
    chmod +x gucci && \
    mv gucci /usr/bin

COPY --from=builder /usr/local/sbin/haproxy /usr/sbin/haproxy
RUN mkdir /var/lib/haproxy
ADD haproxy.conf /etc/haproxy/haproxy.cfg.tpl
ADD startup.sh /startup.sh
ADD stdlogs.yml /stdlogs.yml
ADD check-frontend.sh /check-frontend.sh

ARG buildTime
ENV buildTime="$buildTime"

ENTRYPOINT []
CMD ["/startup.sh"]
