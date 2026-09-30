#!/bin/sh
# rusthinq container entrypoint.
#
# rusthinq-cloud is configured by a TOML file. This script picks one of:
#
#   1. config.toml, if it exists -- the user owns the config, and every
#      RUSTHINQ_* variable below is ignored. It is /data/config.toml, except in
#      the Home Assistant add-on, where /data is out of the user's reach and it is
#      /config/config.toml instead (the add-on's own config directory).
#   2. Otherwise a config generated from the RUSTHINQ_* environment variables
#      (written to /data/config.generated.toml on every start). This is what the
#      Home Assistant add-on uses, and the simplest path for plain `docker run`.
#
# Every path in the config is relative to the config's directory, so /data holds
# everything that must survive a restart: the CA (ca.key / ca.cert -- devices
# pin it, losing it means re-provisioning every appliance), the generated
# config, and, when enabled, the bridge's LG credentials in ./state.
#
# Rhai device scripts are kept apart from that, in /scripts, so a host directory
# can be bind-mounted there and edited in place (the script watcher reloads them
# without a restart) without exposing the CA key next to them.
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
    # JSON escapes also work in TOML basic strings. TOML additionally requires
    # DEL to be escaped; slurping stdin preserves trailing newlines in passwords.
    printf '%s' "$1" | jq -Rs '@json | gsub("\u007f"; "\\u007f")' -r
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

# generate_config [path prefix] -- the prefix is put in front of every file path, so
# a copy of the output kept elsewhere still points at the files in $DATA_DIR.
generate_config() {
    p="${1:-}"
    printf 'hostname = %s\n' "$(toml_str "${RUSTHINQ_HOSTNAME:-rusthinq.lan}")"
    if bool "${RUSTHINQ_ADVERTISE_REQUESTED_HOST:-true}"; then
        echo 'advertise_requested_host = true'
    fi
    printf 'ca_key_file = %s\n' "$(toml_str "${p}ca.key")"
    printf 'ca_cert_file = %s\n' "$(toml_str "${p}ca.cert")"
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

    if bool "${RUSTHINQ_BRIDGE:-true}"; then
        echo
        echo '[bridge]'
        printf 'storage_path = %s\n' "$(toml_str "${p:-./}state")"
        # The LG hostnames are redirected to rusthinq, so the bridge defaults to DoH by
        # IP address to get past that; set it empty to use the host's resolver. (The
        # add-on always passes its own bridge_dns option, cleared means empty.)
        if [ "$HA_ADDON" = true ]; then
            bridge_dns="${RUSTHINQ_BRIDGE_DNS:-}"
        else
            bridge_dns="${RUSTHINQ_BRIDGE_DNS-https://1.1.1.1/dns-query,https://8.8.8.8/dns-query}"
        fi
        if [ -n "$bridge_dns" ]; then
            printf 'dns = %s\n' "$(toml_list "$bridge_dns")"
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

    if bool "${RUSTHINQ_GUI:-true}"; then
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
HA_ADDON=false
load_ha_options() {
    file="${RUSTHINQ_OPTIONS_FILE:-$DATA_DIR/options.json}"
    if [ -z "${SUPERVISOR_TOKEN:-}" ] && ! bool "${RUSTHINQ_LOAD_OPTIONS:-}"; then
        return 0
    fi
    [ -f "$file" ] || return 0
    HA_ADDON=true
    eval "$(jq -r 'to_entries[] | select(.value != null)
        | "export RUSTHINQ_\(.key | ascii_upcase)=\(.value | tostring | @sh)"' "$file")"
    # The add-on's /config (the add-on's own config directory, visible to the user)
    # is where scripts and a hand-written config.toml belong -- /data is private to
    # the add-on.
    export RUSTHINQ_SCRIPTS_DIR="${RUSTHINQ_SCRIPTS_DIR:-/config/scripts}"
    export RUSTHINQ_CONFIG_DIR="${RUSTHINQ_CONFIG_DIR:-/config}"
    # A hand-written config.toml names its own broker.
    if [ -z "${RUSTHINQ_MQTT_URL:-}" ] && [ ! -f "$RUSTHINQ_CONFIG_DIR/config.toml" ]; then
        supervisor_mqtt
    fi
}

# No mqtt_url in the add-on options: use the broker the Supervisor knows about (the
# Mosquitto add-on, with a login made for this add-on). A broker set up directly in
# the MQTT integration is not visible there, so that one needs mqtt_url. There is no
# broker to fall back to, so starting without one would only publish into nothing.
supervisor_mqtt() {
    url="${RUSTHINQ_SUPERVISOR_URL:-http://supervisor}/services/mqtt"
    if ! resp=$(wget -qO- --header "Authorization: Bearer ${SUPERVISOR_TOKEN:-}" "$url" 2>/dev/null) ||
        ! mqtt=$(printf '%s' "$resp" | jq -er '.data | select(.host and .port)
            | "mqtt_host=\(.host | @sh) mqtt_port=\(.port | tostring | @sh)",
              "mqtt_scheme=\(if .ssl then "mqtts" else "mqtt" end)",
              "mqtt_user=\(.username // "" | @sh) mqtt_pass=\(.password // "" | @sh)"' 2>/dev/null); then
        die "no MQTT broker: the Supervisor did not provide one. Install the Mosquitto" \
            "broker add-on, or set the mqtt_url option to your own broker."
    fi
    mqtt_host='' mqtt_port='' mqtt_scheme='' mqtt_user='' mqtt_pass=''
    eval "$mqtt"
    # The Supervisor names the broker by its add-on hostname (core-mosquitto), which
    # lives in the add-ons' internal DNS. On the host network that may not resolve,
    # but the Mosquitto add-on publishes the same port on the host.
    if ! getent hosts "$mqtt_host" >/dev/null 2>&1; then
        echo "rusthinq: $mqtt_host does not resolve on the host network, using localhost:$mqtt_port"
        mqtt_host=localhost
    fi
    export RUSTHINQ_MQTT_URL="$mqtt_scheme://$mqtt_host:$mqtt_port"
    export RUSTHINQ_MQTT_USER="$mqtt_user" RUSTHINQ_MQTT_PASSWORD="$mqtt_pass"
    echo "rusthinq: using the Supervisor's MQTT broker at $RUSTHINQ_MQTT_URL"
}

if [ $# -gt 0 ]; then
    cd "$DATA_DIR" 2>/dev/null || true
    exec "$@"
fi

load_ha_options

SCRIPTS_DIR="${RUSTHINQ_SCRIPTS_DIR:-/scripts}"

mkdir -p "$DATA_DIR"
cd "$DATA_DIR"

USER_CONFIG="${RUSTHINQ_CONFIG_DIR:-$DATA_DIR}/config.toml"
if [ -f "$USER_CONFIG" ]; then
    CONFIG="$USER_CONFIG"
    echo "rusthinq: using $CONFIG (RUSTHINQ_* settings are ignored)"
else
    CONFIG="$DATA_DIR/config.generated.toml"
    # The generated file can hold the MQTT and dashboard passwords.
    (umask 077 && generate_config > "$CONFIG")
    echo "rusthinq: generated $CONFIG from the environment"
fi

# In the add-on, leave a starting point for a hand-written config.toml where the user
# can see it: the current options, with the paths spelled out so that a copy renamed
# to config.toml keeps using the CA and bridge state in /data. Relative paths in a
# config.toml under /config would resolve there, and a CA created afresh is one no
# appliance trusts. Rewritten on every start and never read back.
if [ "$HA_ADDON" = true ] && [ -d "$RUSTHINQ_CONFIG_DIR" ]; then
    (umask 077 && generate_config "$DATA_DIR/" > "$RUSTHINQ_CONFIG_DIR/config.toml.example") 2>/dev/null ||
        echo "rusthinq: warning: could not write $RUSTHINQ_CONFIG_DIR/config.toml.example" >&2
fi

if bool "${RUSTHINQ_DRY_RUN:-}"; then
    cat "$CONFIG"
    exit 0
fi

# rhai_dir must exist before the script watcher starts.
if bool "${RUSTHINQ_SCRIPTING:-true}" || [ -f "$USER_CONFIG" ]; then
    mkdir -p "$SCRIPTS_DIR" 2>/dev/null || true
fi

exec rusthinq-cloud "$CONFIG"
