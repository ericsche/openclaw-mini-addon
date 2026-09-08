# OpenClaw Mini

A deliberately small Home Assistant add-on that runs the OpenClaw gateway.

## Why this exists

The upstream [OpenClawHomeAssistant](https://github.com/techartdev/OpenClawHomeAssistant)
add-on is capable but large (~1600 lines of `run.sh`). More importantly, it has no
way to take the gateway offline, which makes two OpenClaw commands impossible to run:

```
StateDatabaseCoordinatorContentionError: another OpenClaw process owns gateway-lifecycle
```

`openclaw doctor --fix` and `openclaw update` both require the gateway to be
**stopped**. A supervised container restarts it instantly, so the lock is never free.

This add-on solves that with a **maintenance flag** the supervisor honours, exposed
through a single command: `oc-maint`.

## What it does and does not do

| Included | Not included |
|---|---|
| OpenClaw gateway, supervised with backoff | Chromium / browser automation |
| Web terminal (ttyd) on the HA sidebar via Ingress | Homebrew, proxy shim, Tailscale relay |
| Maintenance mode (`oc-maint`) | Assist pipeline / OpenAI-compatible endpoint |
| Persistent config, workspace and npm globals in `/config` | Dashboard embedded in the HA panel |
| LAN or loopback bind, auto-generated auth token | Prebuilt image (builds on your machine) |
| Optional update on boot, optional device auto-approval | aarch64, armv7 |

If you need any of the right-hand column, use the upstream add-on instead.

## Install

1. Home Assistant → **Settings → Add-ons → Add-on store**
2. **⋮ → Repositories** → add this repository URL
3. Install **OpenClaw Mini**, then **Start**

The dashboard is at `http://<home-assistant-ip>:18789/`.

## Configuration

| Option | Default | Meaning |
|---|---|---|
| `timezone` | `Europe/Paris` | Container timezone |
| `gateway_port` | `18789` | Gateway WebSocket + dashboard port |
| `gateway_bind_mode` | `lan` | `lan` to reach it from your network, `loopback` for local only |
| `gateway_token` | *(empty)* | Auth token. Generated automatically if empty and bind is `lan` |
| `allowed_origins` | *(empty)* | Comma-separated browser origins allowed to open the Control UI, e.g. `http://192.168.1.50:18789` |
| `enable_terminal` | `true` | Web terminal in the Home Assistant sidebar, through Ingress |
| `auto_approve_devices` | `false` | Approve Control UI browser pairing automatically. Only needed if you disable the terminal |
| `auto_update` | `false` | Install `openclaw@latest` on every start, before the gateway boots |

> With `gateway_bind_mode: loopback` the mapped port is unreachable from your LAN.
> That mode is only useful if you connect from inside the container.

Retrieve the generated token with `oc-maint token`, or read it from the add-on log
on first start.

## Operating it

Open a shell in the add-on container (SSH add-on, or `docker exec` on the host) and use:

```bash
oc-maint status     # port, PID, listener, maintenance state
oc-maint stop       # pause the supervisor and stop the gateway
oc-maint start      # resume
oc-maint restart
oc-maint doctor     # stop -> openclaw doctor --fix -> restart
oc-maint update     # stop -> install openclaw@latest -> repair -> restart
oc-maint token      # print the gateway auth token
oc-maint devices    # list Control UI devices
oc-maint approve <id>   # approve a browser pairing request
```

Get a shell from the **OpenClaw** entry in the Home Assistant sidebar. No SSH add-on,
no Docker access and no exposed port are needed — Ingress handles authentication.

If you prefer Docker:

```bash
docker exec -it $(docker ps --format '{{.Names}}' | grep openclaw_mini) bash
```

### Do not run these

- `openclaw update` — drives service management and a post-update doctor that
  cannot work in a container. Use `oc-maint update`.
- `openclaw gateway stop` / `restart` — there is no systemd here. Use `oc-maint`.
- `export OPENCLAW_STATE_DIR=...` / `OPENCLAW_CONFIG_PATH=...` / `OPENCLAW_HOME=...` —
  OpenClaw then treats the state tree as *isolated* and disables doctor repairs and
  service management. `HOME=/config` is already set for you; that is all it needs.

## Design notes

- **The web terminal is supervised independently of the gateway.** It has to stay
  reachable precisely when the gateway is broken, since that is when you need
  `oc-maint doctor`.
- **Boolean options are read with an explicit null test, not `//`.** jq's `//`
  falls back on `false` as well as `null`, which silently turned `false` options
  back into their defaults.
- **The base image is pinned, not taken from `BUILD_FROM`.** The Supervisor passes
  `BUILD_FROM` pointing at a Home Assistant Alpine base image, which silently
  overrides any default declared in the Dockerfile and breaks the build
  (`apt-get: not found`). OpenClaw needs Node 24, so the Dockerfile starts from
  `node:24-bookworm-slim` directly and ignores `BUILD_FROM` entirely.
- **Health is measured by the listening socket, not by a PID.** `openclaw gateway run`
  is a wrapper that may fork the real daemon, so the child PID is unreliable.
  Polling the port sidesteps the whole problem.
- **The wrapper's exit code is still used**, but only to fail fast: a non-zero exit
  means a hard failure, a zero exit just means it forked.
- **Restart backoff** is 5s per consecutive failure, capped at 60s.
- **`/config` holds everything persistent**: `.openclaw` (state), `clawd` (workspace),
  `.node_global` (npm globals, so updates survive an add-on rebuild).
- **The add-on config write is a merge**, never an overwrite: only `gateway.mode`,
  `port`, `bind`, `auth` and `controlUi.allowedOrigins` are touched. Everything else
  you set in `openclaw.json` is preserved.

## Layout

```
repository.yaml
openclaw_mini/
  config.yaml       add-on manifest (options, schema, ports, mappings)
  Dockerfile        node 24 + openclaw + a handful of CLI tools
  run.sh            entrypoint: options -> config -> supervisor loop
  oc-maint          operator CLI (maintenance mode lives here)
  oc-common.sh      shared helpers
  translations/     option labels shown in the Home Assistant UI
  CHANGELOG.md
  DOCS.md           add-on documentation tab
tests/
  test-supervisor.sh     boot, recovery, maintenance, shutdown
  test-failure-path.sh   fast-fail, backoff, resilience
  test-terminal.sh       ingress terminal lifecycle and enable/disable
  test-auto-approve.sh   Control UI pairing auto-approval
```

## Tests

The supervisor and `oc-maint` are covered by stubbed integration tests that need
neither a container nor an OpenClaw install:

```bash
./tests/test-supervisor.sh   ./openclaw_mini
./tests/test-failure-path.sh ./openclaw_mini
```

## License

MIT
