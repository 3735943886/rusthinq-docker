# shellcheck shell=sh
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

