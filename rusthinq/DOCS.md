# Rusthinq add-on

Runs [rusthinq](https://github.com/3735943886/rusthinq) on Home Assistant. Rusthinq
publishes everything to MQTT, so Home Assistant needs an MQTT broker (the Mosquitto
add-on) and something that turns rusthinq's topics into entities; rusthinq itself
knows nothing about Home Assistant.

## Before you start

- Appliances must be able to reach this host on **443**, **8883**, **46030** and
  **47878**. The add-on runs on the host network for that reason, so nothing else on
  the Home Assistant host may be using those ports.
- Point the appliances at rusthinq, by DNS or a router redirect, as described in the
  [rethink installation guide](https://github.com/anszom/rethink/wiki/Installing-rethink‐cloud).
  `hostname` below is the name they will be told to use, so it has to resolve to this
  host on your network. It can't be an IP address.
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
| `hostname` | `rusthinq.local` | The name appliances are told to connect to. |
| `advertise_requested_host` | off | Answer with the name an appliance asked for instead of `hostname`. Only for appliances redirected at the router. |
| `mqtt_url` | `mqtt://localhost:1883` | MQTT broker. |
| `mqtt_user`, `mqtt_password` | empty | Broker login. The Mosquitto add-on requires one. |
| `prefix` | `rusthinq` | Topic prefix for rusthinq's own topics. |
| `raw_prefix`, `raw` | `rusthinq-raw`, `rx,tx,clip_tx,inject,inject_clip,emit` | The raw wire-frame bus (see rusthinq's `config.toml`). |
| `bridge` | off | Forward adopted appliances to the real LG cloud, so the LG app keeps working. Log in from the dashboard or over MQTT. |
| `bridge_dns` | empty | DNS servers the bridge uses (comma separated DoH URLs or addresses) when this host's own resolver points the LG hostnames back at rusthinq. |
| `scripting` | on | Rhai device scripts. Put `<modelId>.rhai` files in the add-on's config folder, under `scripts/`. |
| `il_prefix` | empty | Let scripts publish an IL device descriptor under this prefix. |
| `gui`, `gui_port`, `gui_user`, `gui_password` | off, `44401` | The web dashboard. Set a user and password: it can enable the bridge and read raw traffic. |
| `log` | `status,HTTPS,bridge` | Log topics, comma separated. |

## What the options don't cover

Other ports, `custom_root_cert_file` and the rest of rusthinq's
[`config.toml`](https://github.com/3735943886/rusthinq/blob/master/config.toml) are not
exposed here. For those, run the same image with plain Docker and your own
`config.toml` (see the repository README).
