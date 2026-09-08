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
| OpenClaw gateway, supervised with backoff | Home Assistant Ingress / sidebar panel |
| Persistent config, workspace and npm globals in `/config` | Web terminal (ttyd) — use the SSH add-on |
| Maintenance mode (`oc-maint`) | Chromium / browser automation |
| LAN or loopback bind, auto-generated auth token | Homebrew, proxy shim, Tailscale relay |
| Optional update on boot | Assist pipeline / OpenAI-compatible endpoint |
| amd64 | aarch64, armv7 |

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
```

### Do not run these

- `openclaw update` — drives service management and a post-update doctor that
  cannot work in a container. Use `oc-maint update`.
- `openclaw gateway stop` / `restart` — there is no systemd here. Use `oc-maint`.
- `export OPENCLAW_STATE_DIR=...` / `OPENCLAW_CONFIG_PATH=...` / `OPENCLAW_HOME=...` —
  OpenClaw then treats the state tree as *isolated* and disables doctor repairs and
  service management. `HOME=/config` is already set for you; that is all it needs.

## Design notes

- **Health is measured by the listening socket, not by a PID.** `openclaw gateway run`
  is a wrapper that may fork the real daemon, so the child PID is unreliable.
  Polling the port sidesteps the whole problem.
- **The wrapper's exit code is still used**, but only to fail fast: a non-zero exit
  means a hard failure, a zero exit just means it forked.
- **Restart backoff** is 5s per consecutive failure, capped at 60s.
- **`/config` holds everything persistent**: `.openclaw` (state), `clawd` (workspace),
  `.node_global` (npm globals, so updates survive an add-on rebuild).
- **The add-on config write is a merge**, never an overwrite: only `gateway.mode`,
  `port`, `bind` and `auth` are touched. Everything else you set in
  `openclaw.json` is preserved.

## Layout

```
repository.yaml
openclaw_mini/
  config.yaml       add-on manifest (options, schema, ports, mappings)
  build.yaml        base image
  Dockerfile        node 24 + openclaw + a handful of CLI tools
  run.sh            entrypoint: options -> config -> supervisor loop
  oc-maint          operator CLI (maintenance mode lives here)
  oc-common.sh      shared helpers
  DOCS.md           add-on documentation tab
tests/
  test-supervisor.sh     boot, recovery, maintenance, shutdown
  test-failure-path.sh   fast-fail, backoff, resilience
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
