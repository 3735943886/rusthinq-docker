#!/bin/sh
# Download the linux release archives of a rusthinq release and unpack their
# binaries into bin/<arch>/, where the Dockerfile expects them.
#
#   scripts/fetch-release.sh v0.1.0
#
# Needs the GitHub CLI, logged in (or GH_TOKEN set) with read access to the
# rusthinq repository -- its releases are only visible to accounts that can
# read the repo.
set -eu

TAG="${1:?usage: $0 <release tag, e.g. v0.1.0>}"
REPO="${RUSTHINQ_REPO:-3735943886/rusthinq}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

gh release download "$TAG" --repo "$REPO" --dir "$WORK" --pattern 'rusthinq-*-linux-*.tar.gz'

# release asset suffix -> the TARGETARCH+TARGETVARIANT buildx uses
for pair in amd64:amd64 aarch64:arm64 armv7:armv7; do
    asset="${pair%%:*}"
    dest="${pair##*:}"
    archive="$WORK/rusthinq-$TAG-linux-$asset.tar.gz"
    [ -f "$archive" ] || { echo "missing $archive" >&2; exit 1; }
    rm -rf "$ROOT/bin/$dest"
    mkdir -p "$ROOT/bin/$dest"
    tar -xzf "$archive" -C "$ROOT/bin/$dest" --strip-components=1
    chmod +x "$ROOT/bin/$dest"/rusthinq-*
done

echo "unpacked $TAG into $ROOT/bin/"
