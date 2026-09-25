#!/bin/sh
# Checks the config docker-entrypoint.sh generates, without starting anything
# (RUSTHINQ_DRY_RUN prints the config and exits). Needs jq and, to check the
# TOML really parses, python3 >= 3.11.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# run <name> [VAR=value ...] -> config in $TMP/<name>.toml
run() {
    name="$1"; shift
    dir="$TMP/$name.data"
    mkdir -p "$dir"
    env -i PATH="$PATH" RUSTHINQ_DATA_DIR="$dir" RUSTHINQ_DRY_RUN=1 "$@" \
        "$ROOT/docker-entrypoint.sh" > "$TMP/$name.out" 2> "$TMP/$name.err" || {
        echo "FAIL $name: entrypoint exited non-zero"; cat "$TMP/$name.err"; fail=1; return
    }
    # drop the "generated ..." status line
    grep -v '^rusthinq: ' "$TMP/$name.out" > "$TMP/$name.toml" || true
    if command -v python3 >/dev/null && python3 -c 'import tomllib' 2>/dev/null; then
        python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$TMP/$name.toml" \
            || { echo "FAIL $name: invalid TOML"; cat "$TMP/$name.toml"; fail=1; }
    fi
}

expect() { # expect <name> <fixed string>
    grep -qF -- "$2" "$TMP/$1.toml" || { echo "FAIL $1: missing: $2"; cat "$TMP/$1.toml"; fail=1; }
}
reject() { # reject <name> <fixed string>
    if grep -qF -- "$2" "$TMP/$1.toml"; then echo "FAIL $1: unexpected: $2"; fail=1; fi
}

run defaults
expect defaults 'hostname = "rusthinq.local"'
expect defaults 'https_port = 443'
expect defaults 'mqtts_port = 8883'
expect defaults 'mqtt_url = "mqtt://localhost:1883"'
expect defaults 'raw_prefix = "rusthinq-raw"'
expect defaults 'rhai_dir = "/scripts"'
reject defaults '[bridge]'
reject defaults '[gui]'

run everything RUSTHINQ_BRIDGE=true RUSTHINQ_BRIDGE_DNS="https://1.1.1.1/dns-query, 8.8.8.8" \
    RUSTHINQ_GUI=True RUSTHINQ_GUI_USER=admin RUSTHINQ_GUI_PASSWORD='p"a\ss' \
    RUSTHINQ_MQTT_PASSWORD="se\"cret\\" RUSTHINQ_LOG="status, incoming"
expect everything '[bridge]'
expect everything 'dns = ["https://1.1.1.1/dns-query", "8.8.8.8"]'
expect everything 'gui_pass = "p\"a\\ss"'
expect everything 'mqtt_pass = "se\"cret\\"'
expect everything 'log = ["status", "incoming"]'

run noraw RUSTHINQ_RAW_PREFIX= RUSTHINQ_SCRIPTING=false
reject noraw 'raw_prefix'
reject noraw '[scripting]'

# Home Assistant: options.json becomes RUSTHINQ_* variables, scripts go to /config.
printf '%s' '{"hostname":"ha.local","bridge":true,"advertise_requested_host":false,"mqtt_user":"u","gui_port":8080,"gui":true,"gui_user":"a","gui_password":"b","il_prefix":null}' \
    > "$TMP/options.json"
run ha SUPERVISOR_TOKEN=x RUSTHINQ_OPTIONS_FILE="$TMP/options.json"
expect ha 'hostname = "ha.local"'
expect ha '[bridge]'
expect ha 'mqtt_user = "u"'
expect ha 'rhai_dir = "/config/scripts"'
expect ha 'gui_port = 8080'
reject ha 'advertise_requested_host'
reject ha 'il_prefix'

# Outside Home Assistant an options.json is left alone.
run plain RUSTHINQ_OPTIONS_FILE="$TMP/options.json"
expect plain 'hostname = "rusthinq.local"'

# A user-owned config.toml wins over the environment.
mkdir -p "$TMP/own.data"
printf 'hostname = "mine.local"\n' > "$TMP/own.data/config.toml"
env -i PATH="$PATH" RUSTHINQ_DATA_DIR="$TMP/own.data" RUSTHINQ_DRY_RUN=1 RUSTHINQ_HOSTNAME=env.local \
    "$ROOT/docker-entrypoint.sh" > "$TMP/own.out"
grep -qF 'hostname = "mine.local"' "$TMP/own.out" || { echo "FAIL own: config.toml not used"; fail=1; }

# A bad port is refused.
if env -i PATH="$PATH" RUSTHINQ_DATA_DIR="$TMP/bad.data" RUSTHINQ_DRY_RUN=1 RUSTHINQ_GUI=1 \
    RUSTHINQ_GUI_PORT=abc "$ROOT/docker-entrypoint.sh" >/dev/null 2>&1; then
    echo "FAIL badport: accepted"; fail=1
fi

[ "$fail" = 0 ] && echo "entrypoint tests passed"
exit "$fail"
