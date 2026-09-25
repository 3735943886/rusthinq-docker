# syntax=docker/dockerfile:1.7
#
# rusthinq -- LG ThinQ local cloud emulator.
#
# This image does not compile anything: it packages the prebuilt static musl
# binaries from a rusthinq GitHub release. Put them in bin/<arch>/ first --
#
#   scripts/fetch-release.sh v0.1.0
#
# -- which fills bin/amd64, bin/arm64 and bin/armv7 (the names buildx gives
# TARGETARCH+TARGETVARIANT). CI does the same before it builds.
#
# rusthinq-cloud shells out to the `openssl` CLI to sign device CSRs, so the
# image needs it even though the binaries link OpenSSL statically. jq is for the
# Home Assistant add-on, which passes its options as /data/options.json.
FROM alpine:3.21

ARG TARGETARCH
ARG TARGETVARIANT
ARG VERSION=dev

LABEL org.opencontainers.image.title="rusthinq" \
      org.opencontainers.image.description="LG ThinQ local cloud emulator" \
      org.opencontainers.image.source="https://github.com/3735943886/rusthinq-docker" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.licenses="GPL-2.0-or-later"

RUN apk add --no-cache openssl ca-certificates tzdata jq

COPY bin/${TARGETARCH}${TARGETVARIANT}/rusthinq-cloud /usr/local/bin/rusthinq-cloud
COPY bin/${TARGETARCH}${TARGETVARIANT}/rusthinq-setup /usr/local/bin/rusthinq-setup
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Everything that has to survive a restart lives here: the CA the appliances
# pin, the generated config, the bridge's LG credentials.
VOLUME /data
WORKDIR /data

# Appliances connect to 443 (HTTPS) and 8883 (MQTTS) on fixed ports, and ThinQ1
# ones to 46030 / 47878, so run with host networking (or publish these as-is).
# 44401 is the optional dashboard. Ports below 1024 are why this runs as root.
EXPOSE 443 8883 46030 47878 44401

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
