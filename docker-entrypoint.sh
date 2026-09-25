#!/bin/sh
# rusthinq container entrypoint.
#
# rusthinq-cloud is configured by a TOML file. This script picks one of:
#
#   1. /data/config.toml, if it exists -- the user owns the config, and every
#      RUSTHINQ_* variable below is ignored.
#   2. Otherwise a config generated from the RUSTHINQ_* environment variables
#      (written to /data/config.generated.toml on every start). This is what the
#      Home Assistant add-on uses, and the simplest path for plain `docker run`.
#
# Every path in the config is relative to the config's directory, so /data holds
# everything that must survive a restart: the CA (ca.key / ca.cert -- devices
# pin it, losing it means re-provisioning every appliance), the generated
# config, and, when enabled, the bridge's LG credentials in ./state.
#
# Any command line arguments replace the default start, e.g.
#   docker run ... rusthinq rusthinq-setup 192.168.120.254 'SSID' 'password'
set -eu
set -f # no globbing while splitting the comma-separated lists below

DATA_DIR="${RUSTHINQ_DATA_DIR:-/data}"

bool() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        1 | true | yes | on) return 0 ;;
        *) return 1 ;;
    esac
}

die() {
    echo "rusthinq: $*" >&2
    exit 1
}

# A TOML basic string.
toml_str() {
    printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

# "a, b,c" -> ["a", "b", "c"]
toml_list() {
    out=""
    old_ifs=$IFS
    IFS=,
    for item in $1; do
        item=$(printf '%s' "$item" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -n "$item" ] || continue
        out="${out:+$out, }$(toml_str "$item")"
    done
    IFS=$old_ifs
    printf '[%s]' "$out"
}

require_port() {
    case "$2" in
        '' | *[!0-9]*) die "$1 must be a port number, got '$2'" ;;
    esac
}

generate_config() {
    printf 'hostname = %s\n' "$(toml_str "${RUSTHINQ_HOSTNAME:-rusthinq.local}")"
    if bool "${RUSTHINQ_ADVERTISE_REQUESTED_HOST:-}"; then
        echo 'advertise_requested_host = true'
    fi
    echo 'ca_key_file = "ca.key"'
    echo 'ca_cert_file = "ca.cert"'
    echo 'https_port = 443'
    echo 'mqtts_port = 8883'
    printf 'log = %s\n' "$(toml_list "${RUSTHINQ_LOG:-status,HTTPS,bridge}")"

    echo
    echo '[mqtt]'
    printf 'mqtt_url = %s\n' "$(toml_str "${RUSTHINQ_MQTT_URL:-mqtt://localhost:1883}")"
    printf 'mqtt_user = %s\n' "$(toml_str "${RUSTHINQ_MQTT_USER:-}")"
    printf 'mqtt_pass = %s\n' "$(toml_str "${RUSTHINQ_MQTT_PASSWORD:-}")"
    printf 'rusthinq_prefix = %s\n' "$(toml_str "${RUSTHINQ_PREFIX:-rusthinq}")"
    # Unset -> default; set but empty -> the raw bus stays off.
    raw_prefix="${RUSTHINQ_RAW_PREFIX-rusthinq-raw}"
    if [ -n "$raw_prefix" ]; then
        printf 'raw_prefix = %s\n' "$(toml_str "$raw_prefix")"
        printf 'raw = %s\n' "$(toml_list "${RUSTHINQ_RAW:-rx,tx,clip_tx,inject,inject_clip,emit}")"
    fi

    if bool "${RUSTHINQ_BRIDGE:-}"; then
        echo
        echo '[bridge]'
        echo 'storage_path = "./state"'
        if [ -n "${RUSTHINQ_BRIDGE_DNS:-}" ]; then
            printf 'dns = %s\n' "$(toml_list "$RUSTHINQ_BRIDGE_DNS")"
        fi
    fi

    if bool "${RUSTHINQ_SCRIPTING:-true}"; then
        echo
        echo '[scripting]'
        printf 'rhai_dir = %s\n' "$(toml_str "$SCRIPTS_DIR")"
        echo 'watch = true'
        if [ -n "${RUSTHINQ_IL_PREFIX:-}" ]; then
            printf 'il_prefix = %s\n' "$(toml_str "$RUSTHINQ_IL_PREFIX")"
        fi
    fi

    if bool "${RUSTHINQ_GUI:-}"; then
        gui_port="${RUSTHINQ_GUI_PORT:-44401}"
        require_port RUSTHINQ_GUI_PORT "$gui_port"
        echo
        echo '[gui]'
        printf 'gui_port = %s\n' "$gui_port"
        if [ -n "${RUSTHINQ_GUI_USER:-}" ]; then
            printf 'gui_user = %s\n' "$(toml_str "$RUSTHINQ_GUI_USER")"
            printf 'gui_pass = %s\n' "$(toml_str "${RUSTHINQ_GUI_PASSWORD:-}")"
        else
            echo "rusthinq: warning: the dashboard is enabled without RUSTHINQ_GUI_USER;" \
                "anyone who can reach port $gui_port can control the bridge" >&2
        fi
    fi
}

# Home Assistant add-on: the Supervisor writes the user's options to
# /data/options.json (add-on `environment:` entries are static, so they can't carry
# option values). Each option becomes the RUSTHINQ_<OPTION> variable of the same
# name, e.g. mqtt_url -> RUSTHINQ_MQTT_URL. Only done inside the add-on
# (SUPERVISOR_TOKEN is set there), or when RUSTHINQ_LOAD_OPTIONS is.
load_ha_options() {
    file="${RUSTHINQ_OPTIONS_FILE:-$DATA_DIR/options.json}"
    if [ -z "${SUPERVISOR_TOKEN:-}" ] && ! bool "${RUSTHINQ_LOAD_OPTIONS:-}"; then
        return 0
    fi
    [ -f "$file" ] || return 0
    eval "$(jq -r 'to_entries[] | select(.value != null)
        | "export RUSTHINQ_\(.key | ascii_upcase)=\(.value | tostring | @sh)"' "$file")"
    # The add-on's /config (the add-on's own config directory, visible to the user)
    # is where scripts belong -- /data is private to the add-on.
    export RUSTHINQ_SCRIPTS_DIR="${RUSTHINQ_SCRIPTS_DIR:-/config/scripts}"
}

if [ $# -gt 0 ]; then
    cd "$DATA_DIR" 2>/dev/null || true
    exec "$@"
fi

load_ha_options

SCRIPTS_DIR="${RUSTHINQ_SCRIPTS_DIR:-./scripts}"

mkdir -p "$DATA_DIR"
cd "$DATA_DIR"

if [ -f "$DATA_DIR/config.toml" ]; then
    CONFIG="$DATA_DIR/config.toml"
    echo "rusthinq: using $CONFIG (RUSTHINQ_* settings are ignored)"
else
    CONFIG="$DATA_DIR/config.generated.toml"
    # The generated file can hold the MQTT and dashboard passwords.
    (umask 077 && generate_config > "$CONFIG")
    echo "rusthinq: generated $CONFIG from the environment"
fi

if bool "${RUSTHINQ_DRY_RUN:-}"; then
    cat "$CONFIG"
    exit 0
fi

# rhai_dir must exist before the script watcher starts.
if bool "${RUSTHINQ_SCRIPTING:-true}" || [ -f "$DATA_DIR/config.toml" ]; then
    mkdir -p "$SCRIPTS_DIR" 2>/dev/null || true
fi

exec rusthinq-cloud "$CONFIG"
