# rusthinq-docker

Docker images and Home Assistant add-ons for [rusthinq](https://github.com/3735943886/rusthinq).
**0.2 is the default runtime; 0.1 remains available for legacy installations.**
Images package upstream static musl release binaries for amd64, arm64 and arm/v7.

| Image | Runtime | Home Assistant add-on |
| --- | --- | --- |
| `3735943886/rusthinq:0.2` | 0.2 (`rusthinq`) | Rusthinq |
| `3735943886/rusthinq:0.1` | legacy 0.1 (`rusthinq-cloud`) | Rusthinq Legacy (0.1) |

Exact release tags are available too. `latest` follows stable 0.2 releases only.
The default add-on currently targets `0.2.0-rc1`; its image must be published before
installation. Updating this repository does not publish images.

## Docker

```sh
docker compose up -d
```

The compose file follows stable 0.2 releases. To run the release candidate before
a stable release, set its image to `3735943886/rusthinq:0.2.0-rc1` after publishing
that image. Appliances need host networking and ports
443, 8883, 46030 and 47878. The dashboard/API uses 44401. Set the dashboard password
in compose before starting. `/data` contains the CA and persistent state; back it up.
`/scripts` contains device drivers from a 0.2-compatible rusthinq-scripts checkout
with `modules/il_common.rhai`. 0.1 drivers using `ctx.publish_il` are incompatible;
0.2 drivers use the `il_common` module for IL publications.

Without `/data/config.toml`, the entrypoint generates the runtime's TOML from
`RUSTHINQ_*` variables. With that file present, it uses your file unchanged.
Paths in a custom TOML are relative to its directory; use absolute paths when moving
configuration. `RUSTHINQ_DRY_RUN=1` prints configuration without initializing the CA
or starting the daemon. Output can contain passwords.

For a fresh 0.2 installation the wrapper creates a CA once. Existing CA files are
never replaced; an incomplete pair stops startup. Custom configurations must provide
their own valid CA. Use separate data and configuration directories for 0.1 and 0.2.

## 0.2 environment

| Variable | Default | Meaning |
| --- | --- | --- |
| `RUSTHINQ_HOSTNAME` | `rusthinq.lan` | DNS name appliances resolve to this host; avoid `.local` |
| `RUSTHINQ_ADVERTISE_REQUESTED_HOST` | true | Advertise the requested appliance hostname |
| `RUSTHINQ_LEGACY_TLS` | true | Legacy appliance TLS compatibility |
| `RUSTHINQ_MQTT_URL` | `mqtt://localhost:1883` | External broker; empty disables it in plain Docker |
| `RUSTHINQ_MQTT_USER`, `RUSTHINQ_MQTT_PASSWORD` | empty | Broker credentials |
| `RUSTHINQ_PREFIX` | `rusthinq` | Driver topic prefix |
| `RUSTHINQ_BRIDGE` | true | Configure the LG cloud account; log in through management |
| `RUSTHINQ_BRIDGE_DNS` | Cloudflare and Google DoH | Comma-separated resolvers; empty uses system DNS |
| `RUSTHINQ_SCRIPTING` | true | Enable watched drivers from `/scripts` |
| `RUSTHINQ_SCRIPTS_DIR` | `/scripts` | Driver directory |
| `RUSTHINQ_MANAGEMENT` | true | Enable management API |
| `RUSTHINQ_GUI` | true | Serve dashboard on the management endpoint |
| `RUSTHINQ_GUI_PORT` | 44401 | Management port |
| `RUSTHINQ_GUI_USER`, `RUSTHINQ_GUI_PASSWORD` | empty | Management authentication |
| `RUSTHINQ_RAW_INJECT_TOGGLE` | false | Allow management raw-injection toggle |

Broker URLs accept `mqtt://host[:port]` and `mqtts://host[:port]`, including bracketed
IPv6. For custom broker CA, driver bindings, listener overrides and other advanced
settings, supply a 0.2 `config.toml`; see upstream `docs/0.2-runtime.md` and
`docs/0.2-operations.md`. `GUI=false` leaves the API available; `MANAGEMENT=false`
disables both. Retired `RAW_PREFIX`, `RAW`, `IL_PREFIX` and `LOG` environment options
are rejected by the 0.2 generator. Legacy settings are documented in
[rusthinq-legacy/DOCS.md](rusthinq-legacy/DOCS.md).

## Logging

Use `RUST_LOG` to control 0.2 daemon logs; there is no TOML log setting.
The default is application `info` and dependency `warn`. For diagnostics, add this
to the compose service's `environment`:

```yaml
RUST_LOG: warn,rusthinq=debug,rusthinq_app=debug
```

`trace` includes packet and publication payloads, which may contain private data.

## Command-line tools

Online 0.2 tools use the management API. Their default endpoint is port 8080;
set `RUSTHINQ_API` to the container's management port (44401 by default).
`RUSTHINQ_USER` and `RUSTHINQ_PASSWORD` are the client credentials matching the
configured management user and password:

```sh
docker exec -e RUSTHINQ_API=http://127.0.0.1:44401/ \
  -e RUSTHINQ_USER=admin -e RUSTHINQ_PASSWORD='your-dashboard-password' \
  rusthinq rusthinqctl devices
```

## Home Assistant

Add `https://github.com/3735943886/rusthinq-docker` in the Add-on Store repository
settings. Install **Rusthinq** for 0.2, or **Rusthinq Legacy (0.1)** for existing legacy
use. Their data/config directories are separate. See the
[0.2 add-on docs](rusthinq/DOCS.md) for options and custom configuration.

SoftAP provisioning needs a PC joined to the appliance Wi-Fi:

```sh
docker run --rm --network host 3735943886/rusthinq:0.2 \
  rusthinq-setup 192.168.120.254 'SSID' 'password'
```

## Releasing

Run the Docker workflow with an upstream release tag or dispatch `rusthinq-release`
with `client_payload.tag`. Release archives retain the naming convention
`rusthinq-vX.Y.Z-linux-{amd64,aarch64,armv7}.tar.gz`, with executables in one top-level
directory. 0.2 archives must include `rusthinq`, `rusthinqctl` (every tool, including
`rusthinqctl migrate`, is a subcommand) and `rusthinq-setup`; all packaged binaries are
copied into the image.

Stable 0.1 releases update `:0.1` and the legacy add-on only. Stable 0.2 releases
update `:0.2`, `:latest`, and the default add-on. Prereleases publish their exact tag
only and do not update add-on metadata. CI validates both entrypoints and metadata.

Secrets: `DOCKER_USERNAME`, `DOCKER_PASSWORD`, and optional `RUSTHINQ_TOKEN` for
private upstream releases. To build locally:

```sh
scripts/fetch-release.sh v0.2.0-rc1
docker buildx build --build-arg VERSION=0.2.0-rc1 \
  --platform linux/amd64,linux/arm64,linux/arm/v7 \
  -t 3735943886/rusthinq:0.2.0-rc1 .
```

## License

GPL-2.0-or-later; see [COPYING](COPYING).
