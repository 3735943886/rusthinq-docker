# Rusthinq 0.2 add-on

The default add-on uses the 0.2 runtime. **Rusthinq Legacy (0.1)** preserves the old
runtime with its own options and separate storage.

Appliances must reach this host on 443, 8883, 46030 and 47878. If Mosquitto publishes
8883, clear its `8883/tcp` host port before starting Rusthinq. Configure your DNS or
router to direct appliance traffic to this host; `hostname` must be a resolvable DNS
name, not `.local`. SoftAP setup still requires a PC on the appliance Wi-Fi.

## Options

`mqtt_url` left empty uses the Supervisor's Mosquitto broker and credentials.
Set it explicitly for another broker. `mqtt_user` and `mqtt_password` provide its
credentials. `prefix` is the driver topic prefix. `scripting` enables drivers in the
add-on config folder's `scripts/` directory. Use 0.2-compatible rusthinq-scripts
with `modules/il_common.rhai`; 0.1 drivers using `ctx.publish_il` are incompatible.

`bridge` configures the LG account checkpoint. Log in and manage pairing in the
0.2 dashboard/API. `bridge_dns` is a comma-separated resolver list; clearing it uses
system DNS. `legacy_tls` defaults to true for older appliances.

`management` enables the API on `gui_port` (44401). `gui` controls the dashboard;
the API remains available with GUI off. Set `gui_user` and `gui_password` before
use. `raw_inject_toggle` defaults to false. Legacy raw MQTT, `il_prefix`, and `log`
options do not exist in this add-on.

On a fresh installation the wrapper creates the CA once in private `/data`.
Back up the add-on: appliances pin this CA. It is never replaced automatically.

## Custom config

Place a 0.2 `config.toml` in the add-on config folder (`/config` inside the add-on).
It overrides options and Supervisor MQTT discovery. `config.toml.example` is written
there at startup with absolute `/data` paths. Custom configuration must reference
an existing valid CA. See upstream runtime/operations guides for the schema.
