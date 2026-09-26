# Rusthinq add-on

Runs [rusthinq](https://github.com/3735943886/rusthinq) on Home Assistant. Rusthinq
publishes everything to MQTT, so Home Assistant needs an MQTT broker (the Mosquitto
add-on) and something that turns rusthinq's topics into entities; rusthinq itself
knows nothing about Home Assistant.

## Before you start

- Appliances must be able to reach this host on **443**, **8883**, **46030** and
  **47878**. The add-on runs on the host network for that reason, so nothing else on
  the Home Assistant host may be using those ports.
- **The Mosquitto add-on takes 8883 by default.** Clear its `8883/tcp` port in
  Mosquitto's **Configuration → Network** section before starting this add-on, or rusthinq
  cannot listen for the appliances' MQTTS connections.
- Point the appliances at rusthinq, by DNS or a router redirect, as described in the
  [rethink installation guide](https://github.com/anszom/rethink/wiki/Installing-rethink‐cloud).
  `hostname` below is the name they will be told to use, so it has to resolve to this
  host through your network's DNS. It can't be an IP address, and a `.local` name won't
  do: that is mDNS, which appliances don't speak.
- The add-on cannot put Wi-Fi credentials into a new appliance (SoftAP setup with
  `rusthinq-setup`): that needs a machine connected to the appliance's own Wi-Fi network,
  which the Home Assistant host normally is not. Do that step from a PC, using the
  release binary or `docker run --rm --network host 3735943886/rusthinq rusthinq-setup ...`,
  and give the appliance the same `hostname` as below. Appliances already paired to LG and
  redirected to rusthinq need no setup step.
- Rusthinq creates its own certificate authority on first start and keeps it in the
  add-on's data. Appliances pin it: once they are set up, **back up this add-on**
  before removing it, or you will have to set them up again.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `hostname` | `rusthinq.lan` | The name appliances are told to connect to. |
| `advertise_requested_host` | off | Answer with the name an appliance asked for instead of `hostname`. Only for appliances redirected at the router. |
| `mqtt_url` | empty | MQTT broker. Leave it empty to use the Mosquitto add-on: the Supervisor hands over its address and a login. Set it (e.g. `mqtt://192.168.1.10:1883`) for any other broker. |
| `mqtt_user`, `mqtt_password` | empty | Broker login, only with your own `mqtt_url`. |
| `prefix` | `rusthinq` | Topic prefix for rusthinq's own topics. |
| `raw_prefix`, `raw` | `rusthinq-raw`, `rx,tx,clip_tx,inject,inject_clip,emit` | The raw wire-frame bus (see rusthinq's `config.toml`). |
| `bridge` | off | Forward adopted appliances to the real LG cloud, so the LG app keeps working. Log in from the dashboard or over MQTT. |
| `bridge_dns` | `https://1.1.1.1/dns-query,https://8.8.8.8/dns-query` | DNS servers the bridge uses to find the real LG servers, past the redirect that points the appliances at rusthinq. Comma separated DoH URLs or addresses; empty uses this host's own resolver. |
| `scripting` | on | Rhai device scripts. Put `<modelId>.rhai` files in the add-on's config folder, under `scripts/`. |
| `il_prefix` | empty | Let scripts publish an IL device descriptor under this prefix. |
| `gui`, `gui_port`, `gui_user`, `gui_password` | off, `44401` | The web dashboard. Set a user and password: it can enable the bridge and read raw traffic. |
| `log` | `status,HTTPS,bridge` | Log topics, comma separated. |

## A hand-written config.toml

The options cover the common cases. For anything else — `custom_root_cert_file`, other
ports, advertised URLs behind a proxy, the rest of rusthinq's
[`config.toml`](https://github.com/3735943886/rusthinq/blob/master/config.toml) — put a
`config.toml` in the add-on's config folder (`/addon_configs/<slug>/` over Samba or SSH,
next to `scripts/`). While it exists every option above is ignored, the MQTT lookup
included.

Start from `config.toml.example`, which the add-on writes there on every start from your
current options. Its file paths point into the add-on's private data (`/data/ca.key`,
`/data/state`), so a copy keeps using the same CA and bridge login. Keep them that way: a
relative `ca_key_file` would make rusthinq create a new CA, and appliances set up with the
old one would have to be set up again. The example holds your MQTT and dashboard
passwords, like the options do.
