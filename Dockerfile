# Server: Caddy (HTTP/1.1, HTTP/2, HTTP/3 über quic-go), selbstsigniertes Zertifikat
FROM caddy:alpine AS server
RUN apk add --no-cache iproute2
COPY Caddyfile /etc/caddy/Caddyfile
COPY www/ /srv/
COPY entrypoint-netem.sh /entrypoint-netem.sh
RUN chmod +x /entrypoint-netem.sh
EXPOSE 443/tcp 443/udp
ENTRYPOINT ["/entrypoint-netem.sh"]
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]

# Client: curl mit HTTP/3 über ngtcp2 + nghttp3 (GnuTLS), selbst gebaut; plus tc/bash und measure.sh
FROM alpine:edge AS curl-ngtcp2-build
ARG CURL_VERSION=8.14.1
RUN apk add --no-cache build-base curl gnutls-dev ngtcp2-dev ngtcp2-gnutls nghttp3-dev nghttp2-dev zlib-dev pkgconf \
 && curl -sSL https://curl.se/download/curl-${CURL_VERSION}.tar.xz | tar xJ -C /tmp \
 && cd /tmp/curl-${CURL_VERSION} \
 && ./configure --prefix=/opt/curl --with-gnutls --with-ngtcp2 --with-nghttp3 --with-nghttp2 \
      --without-libpsl --disable-docs --disable-manual \
 && make -j"$(nproc)" && make install

FROM alpine:edge AS client
RUN apk add --no-cache bash iproute2-tc gnutls ngtcp2 ngtcp2-gnutls nghttp3 nghttp2-libs zlib ca-certificates
COPY --from=curl-ngtcp2-build /opt/curl /opt/curl
ENV PATH=/opt/curl/bin:$PATH
COPY entrypoint-netem.sh /entrypoint-netem.sh
COPY measure.sh /measure.sh
RUN chmod +x /entrypoint-netem.sh /measure.sh
ENTRYPOINT ["/entrypoint-netem.sh"]
CMD ["/measure.sh", "https://server"]
