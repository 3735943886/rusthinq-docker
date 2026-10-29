# syntax=docker/dockerfile:1.7
#
# rusthinq -- LG ThinQ local cloud emulator.
#
# Packages prebuilt static musl binaries from a rusthinq release.
# Fetch them with scripts/fetch-release.sh, then build with VERSION matching
# that release. jq supports configuration generation and HA options.
FROM alpine:3.21

ARG TARGETARCH
ARG TARGETVARIANT
ARG VERSION=0.2.0-rc1

LABEL org.opencontainers.image.title="rusthinq" \
      org.opencontainers.image.description="LG ThinQ local cloud emulator" \
      org.opencontainers.image.source="https://github.com/3735943886/rusthinq-docker" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.licenses="GPL-2.0-or-later"

RUN apk add --no-cache openssl ca-certificates tzdata jq \
 && mkdir -p /scripts

COPY bin/${TARGETARCH}${TARGETVARIANT}/ /usr/local/bin/
COPY config/ /usr/local/lib/rusthinq/
RUN case "$VERSION" in \
      0.1.*) series=0.1; test -x /usr/local/bin/rusthinq-cloud ;; \
      0.2.*) series=0.2; test -x /usr/local/bin/rusthinq; test -x /usr/local/bin/rusthinqctl ;; \
      *) echo "Unsupported VERSION: $VERSION" >&2; exit 1 ;; \
    esac && printf '%s\n' "$series" > /etc/rusthinq-series
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Everything that has to survive a restart lives here: the CA the appliances
# pin, the generated config, the bridge's LG credentials.
VOLUME /data
WORKDIR /data

# Rhai device scripts (RUSTHINQ_SCRIPTS_DIR). Not a VOLUME on purpose: bind-mount a
# host directory here to edit them from outside; they are reloaded on change.

# Appliances connect to 443 (HTTPS) and 8883 (MQTTS) on fixed ports, and ThinQ1
# ones to 46030 / 47878, so run with host networking (or publish these as-is).
# 44401 is the optional dashboard. Ports below 1024 are why this runs as root.
EXPOSE 443 8883 46030 47878 44401

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
