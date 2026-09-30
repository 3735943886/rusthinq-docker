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
expect defaults 'hostname = "rusthinq.lan"'
expect defaults 'https_port = 443'
expect defaults 'mqtts_port = 8883'
expect defaults 'mqtt_url = "mqtt://localhost:1883"'
expect defaults 'raw_prefix = "rusthinq-raw"'
expect defaults 'rhai_dir = "/scripts"'
expect defaults 'log = ["status", "HTTPS", "bridge"]'
expect defaults 'advertise_requested_host = true'
expect defaults '[bridge]'
expect defaults 'dns = ["https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"]'
expect defaults 'gui_port = 44401'

run off RUSTHINQ_BRIDGE=false RUSTHINQ_GUI=false RUSTHINQ_ADVERTISE_REQUESTED_HOST=false
reject off '[bridge]'
reject off '[gui]'
reject off 'advertise_requested_host'

run hostdns RUSTHINQ_BRIDGE_DNS=
expect hostdns '[bridge]'
reject hostdns 'dns = '

run everything RUSTHINQ_BRIDGE=true RUSTHINQ_BRIDGE_DNS="https://1.1.1.1/dns-query, 8.8.8.8" \
    RUSTHINQ_GUI=True RUSTHINQ_GUI_USER=admin RUSTHINQ_GUI_PASSWORD='p"a\ss' \
    RUSTHINQ_MQTT_PASSWORD="se\"cret\\" RUSTHINQ_LOG="status, incoming"
expect everything '[bridge]'
expect everything 'dns = ["https://1.1.1.1/dns-query", "8.8.8.8"]'
expect everything 'gui_pass = "p\"a\\ss"'
expect everything 'mqtt_pass = "se\"cret\\"'
expect everything 'log = ["status", "incoming"]'

# Passwords must survive TOML serialization, including trailing newlines and
# every control character that can be carried in an environment variable.
if command -v python3 >/dev/null && python3 -c 'import tomllib' 2>/dev/null; then
    python3 - "$ROOT" "$TMP" <<'PY' || fail=1
import os
from pathlib import Path
import subprocess
import sys
import tomllib

root, tmp = map(Path, sys.argv[1:])
passwords = ['line1\nline2', 'trailing\n\n', ''.join(map(chr, range(1, 32))) + '\x7f', '한글"\\password']
for index, password in enumerate(passwords):
    data = tmp / f'password-{index}'
    env = {
        'PATH': os.environ['PATH'],
        'RUSTHINQ_DATA_DIR': str(data),
        'RUSTHINQ_DRY_RUN': '1',
        'RUSTHINQ_MQTT_PASSWORD': password,
        'RUSTHINQ_GUI_USER': 'admin',
        'RUSTHINQ_GUI_PASSWORD': password,
    }
    subprocess.run([str(root / 'docker-entrypoint.sh')], env=env, check=True, capture_output=True)
    config = tomllib.loads((data / 'config.generated.toml').read_text())
    assert config['mqtt']['mqtt_pass'] == password, f'MQTT password roundtrip failed: {index}'
    assert config['gui']['gui_pass'] == password, f'GUI password roundtrip failed: {index}'
PY
fi

run noraw RUSTHINQ_RAW_PREFIX= RUSTHINQ_SCRIPTING=false
reject noraw 'raw_prefix'
reject noraw '[scripting]'

# Home Assistant: options.json becomes RUSTHINQ_* variables, scripts go to /config.
printf '%s' '{"hostname":"ha.local","bridge":true,"mqtt_url":"mqtt://10.0.0.5:1883","advertise_requested_host":false,"mqtt_user":"u","gui_port":8080,"gui":true,"gui_user":"a","gui_password":"b","il_prefix":null}' \
    > "$TMP/options.json"
run ha SUPERVISOR_TOKEN=x RUSTHINQ_OPTIONS_FILE="$TMP/options.json" RUSTHINQ_CONFIG_DIR="$TMP/nowhere"
expect ha 'hostname = "ha.local"'
expect ha 'mqtt_url = "mqtt://10.0.0.5:1883"'
expect ha '[bridge]'
expect ha 'mqtt_user = "u"'
expect ha 'rhai_dir = "/config/scripts"'
expect ha 'gui_port = 8080'
reject ha 'advertise_requested_host'
reject ha 'il_prefix'

# The add-on writes config.toml.example to its config directory, with the paths
# pointing back into the data directory.
mkdir -p "$TMP/haconf"
run haexample SUPERVISOR_TOKEN=x RUSTHINQ_OPTIONS_FILE="$TMP/options.json" RUSTHINQ_CONFIG_DIR="$TMP/haconf"
ex="$TMP/haconf/config.toml.example"
if [ -f "$ex" ]; then
    grep -qF "ca_key_file = \"$TMP/haexample.data/ca.key\"" "$ex" || { echo "FAIL haexample: ca path"; cat "$ex"; fail=1; }
    grep -qF "storage_path = \"$TMP/haexample.data/state\"" "$ex" || { echo "FAIL haexample: state path"; cat "$ex"; fail=1; }
else
    echo "FAIL haexample: no config.toml.example"; fail=1
fi
expect haexample 'ca_key_file = "ca.key"'
expect haexample 'storage_path = "./state"'

# ... and a config.toml there wins over the options.
printf 'hostname = "hand.lan"\n' > "$TMP/haconf/config.toml"
env -i PATH="$PATH" RUSTHINQ_DATA_DIR="$TMP/haown.data" RUSTHINQ_DRY_RUN=1 SUPERVISOR_TOKEN=x \
    RUSTHINQ_OPTIONS_FILE="$TMP/options.json" RUSTHINQ_CONFIG_DIR="$TMP/haconf" \
    "$ROOT/docker-entrypoint.sh" > "$TMP/haown.out"
grep -qF 'hostname = "hand.lan"' "$TMP/haown.out" || { echo "FAIL haown: config.toml not used"; fail=1; }
# ... without asking the Supervisor for a broker (nothing answers here).
printf '%s' '{"mqtt_url":""}' > "$TMP/nourl.json"
env -i PATH="$PATH" RUSTHINQ_DATA_DIR="$TMP/haown2.data" RUSTHINQ_DRY_RUN=1 SUPERVISOR_TOKEN=x \
    RUSTHINQ_OPTIONS_FILE="$TMP/nourl.json" RUSTHINQ_CONFIG_DIR="$TMP/haconf" \
    RUSTHINQ_SUPERVISOR_URL="http://127.0.0.1:9" "$ROOT/docker-entrypoint.sh" > "$TMP/haown2.out" 2>&1 ||
    { echo "FAIL haown2: config.toml did not skip the Supervisor lookup"; cat "$TMP/haown2.out"; fail=1; }

# No mqtt_url: the broker comes from the Supervisor's MQTT service.
if command -v python3 >/dev/null && command -v wget >/dev/null; then
    mkdir -p "$TMP/sv/services"
    printf '%s' '{"result":"ok","data":{"host":"core-mosquitto.invalid","port":1883,"ssl":false,"username":"addons","password":"p w"}}' \
        > "$TMP/sv/services/mqtt"
    port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
    python3 -m http.server -b 127.0.0.1 -d "$TMP/sv" "$port" >/dev/null 2>&1 &
    srv=$!
    i=0; until wget -qO- "http://127.0.0.1:$port/services/mqtt" >/dev/null 2>&1 || [ $i -ge 50 ]; do
        i=$((i + 1)); sleep 0.1
    done
    run supervisor SUPERVISOR_TOKEN=x RUSTHINQ_OPTIONS_FILE="$TMP/nourl.json" \
        RUSTHINQ_CONFIG_DIR="$TMP/nowhere" RUSTHINQ_SUPERVISOR_URL="http://127.0.0.1:$port"
    expect supervisor 'mqtt_url = "mqtt://localhost:1883"'
    expect supervisor 'mqtt_user = "addons"'
    expect supervisor 'mqtt_pass = "p w"'
    kill "$srv"
    # With nothing answering, starting without a broker is refused.
    if env -i PATH="$PATH" RUSTHINQ_DATA_DIR="$TMP/nobroker.data" RUSTHINQ_DRY_RUN=1 SUPERVISOR_TOKEN=x \
        RUSTHINQ_OPTIONS_FILE="$TMP/nourl.json" RUSTHINQ_CONFIG_DIR="$TMP/nowhere" \
        RUSTHINQ_SUPERVISOR_URL="http://127.0.0.1:$port" "$ROOT/docker-entrypoint.sh" >/dev/null 2>&1; then
        echo "FAIL nobroker: accepted"; fail=1
    fi
else
    echo "skipping the Supervisor MQTT tests (needs python3 and wget)"
fi

# Outside Home Assistant an options.json is left alone.
run plain RUSTHINQ_OPTIONS_FILE="$TMP/options.json"
expect plain 'hostname = "rusthinq.lan"'

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
