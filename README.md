# rusthinq-docker

Docker image and Home Assistant add-on for [rusthinq](https://github.com/3735943886/rusthinq),
the LG ThinQ local cloud emulator.

Nothing is compiled here. The image packages the static musl binaries
(`rusthinq-cloud`, `rusthinq-setup`) from a rusthinq release for `linux/amd64`,
`linux/arm64` and `linux/arm/v7`; the add-on is a thin wrapper around that image.

## Docker

```bash
docker run -d --name rusthinq --restart unless-stopped --network host \
  -v "$PWD/data:/data" \
  -v "$PWD/scripts:/scripts" \
  -e RUSTHINQ_HOSTNAME=rusthinq.local \
  -e RUSTHINQ_MQTT_URL=mqtt://localhost:1883 \
  3735943886/rusthinq
```

or `docker compose up -d` with the [docker-compose.yml](docker-compose.yml) here.

Appliances connect to fixed ports (443, 8883, and 46030/47878 for ThinQ1) that they find
through DNS or a router redirect, so use host networking (or publish those ports as they
are). The container runs as root because those ports are below 1024.

`/data` holds everything that has to survive a restart. **Back it up.** In particular
`ca.key` / `ca.cert` is the certificate authority appliances pin when they are set up;
lose it and every appliance has to be set up again.

`/scripts` holds the Rhai device scripts (`<modelId>.rhai`). Bind-mount a host directory
there and edit them in place: rusthinq watches the directory and reloads a script when it
changes, no restart needed. It is kept out of `/data` so the scripts can be shared or put
under version control without the CA key next to them.

Initial appliance setup (SoftAP adoption, or DNS redirection for appliances already paired
to LG) is described in the
[rethink installation guide](https://github.com/anszom/rethink/wiki/Installing-rethink‐cloud).
The setup tool is in the image:

```bash
docker run --rm --network host 3735943886/rusthinq rusthinq-setup 192.168.120.254 'SSID' 'password'
```

This has to run on a machine that is connected to the appliance's own SoftAP Wi-Fi
(`192.168.120.254`), so use a laptop or PC. It is not something the Home Assistant add-on
can do (see below).

### Configuration

Either environment variables, or your own `config.toml`:

- **Environment.** Without a `config.toml` in `/data`, one is generated from the variables
  below on every start (into `/data/config.generated.toml`).
- **Your own file.** Put a `config.toml` in `/data` and every `RUSTHINQ_*` variable is
  ignored. [rusthinq's config.toml](https://github.com/3735943886/rusthinq/blob/master/config.toml)
  documents every setting; paths in it are relative to `/data`. If you start with the
  environment and switch later, keep `ca.key` and `ca.cert` (they stay in `/data`).

| Variable | Default | Meaning |
| --- | --- | --- |
| `RUSTHINQ_HOSTNAME` | `rusthinq.local` | Name appliances are told to connect to (not an IP address) |
| `RUSTHINQ_ADVERTISE_REQUESTED_HOST` | off | Answer with the name the appliance asked for |
| `RUSTHINQ_MQTT_URL` | `mqtt://localhost:1883` | Broker |
| `RUSTHINQ_MQTT_USER`, `RUSTHINQ_MQTT_PASSWORD` | empty | Broker login |
| `RUSTHINQ_PREFIX` | `rusthinq` | Topic prefix |
| `RUSTHINQ_RAW_PREFIX` | `rusthinq-raw` | Raw frame bus prefix; set it empty to turn the bus off |
| `RUSTHINQ_RAW` | `rx,tx,clip_tx,inject,inject_clip,emit` | Raw bus streams |
| `RUSTHINQ_BRIDGE` | off | Forward to the real LG cloud (state in `/data/state`) |
| `RUSTHINQ_BRIDGE_DNS` | empty | DNS / DoH servers for the bridge, comma separated |
| `RUSTHINQ_SCRIPTING` | on | Rhai device scripts from `RUSTHINQ_SCRIPTS_DIR` (default `/scripts`) |
| `RUSTHINQ_IL_PREFIX` | empty | IL descriptor prefix for scripts |
| `RUSTHINQ_GUI` | off | Dashboard on `RUSTHINQ_GUI_PORT` (default 44401) |
| `RUSTHINQ_GUI_USER`, `RUSTHINQ_GUI_PASSWORD` | empty | Dashboard login. Set them: it can control the bridge |
| `RUSTHINQ_LOG` | `status,HTTPS,bridge` | Log topics, comma separated |

`RUSTHINQ_DRY_RUN=1` prints the effective config and exits.

## Home Assistant add-on

1. **Settings → Add-ons → Add-on Store → ⋮ → Repositories**, add
   `https://github.com/3735943886/rusthinq-docker`.
2. Install **Rusthinq**, set the options ([DOCS.md](rusthinq/DOCS.md)) and start it.

The add-on runs on the host network, pulls `3735943886/rusthinq:<add-on version>`, and
turns its options into the same `RUSTHINQ_*` settings as above. Rhai scripts go in the
add-on's config folder under `scripts/`. It needs an MQTT broker (the Mosquitto add-on) and
something that maps rusthinq's topics to entities; rusthinq itself is not Home Assistant
specific.

**No SoftAP provisioning from the add-on.** Putting Wi-Fi credentials into an appliance with
`rusthinq-setup` needs a machine joined to the appliance's SoftAP network, and the add-on
has neither that connection nor a way to run the tool with arguments. Do that step from a PC
(release binary, or the `docker run` above), pointing the appliance at the name in the
add-on's `hostname` option. Appliances that are already paired to LG, and redirected to
rusthinq by DNS or on the router, need no setup step, and the add-on handles them as usual.

## Releasing

Publishing a rusthinq release does not touch this repository by itself. To package one:

- Run the **Docker** workflow with the rusthinq tag (`v0.1.0`), or have rusthinq's release
  workflow send `repository_dispatch` `rusthinq-release` with `client_payload.tag`.
- It downloads that release's linux archives, pushes the multi-arch image
  (`:0.1.0`, plus `:0.1` and `:latest` for a plain `X.Y.Z`), then commits the new version
  into `rusthinq/config.yaml`. The add-on version moves only after the image exists.

Repository secrets: `DOCKER_USERNAME` and `DOCKER_PASSWORD` (Docker Hub), and
`RUSTHINQ_TOKEN`, a token that can read the rusthinq repository's releases (needed while
that repository is private).

To build by hand:

```bash
scripts/fetch-release.sh v0.1.0     # needs `gh`; fills bin/amd64, bin/arm64, bin/armv7
docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -t 3735943886/rusthinq:0.1.0 .
```

## License

rusthinq is GPL-2.0-or-later (see [COPYING](COPYING)); the image redistributes its
binaries, and the files here are under the same license.
