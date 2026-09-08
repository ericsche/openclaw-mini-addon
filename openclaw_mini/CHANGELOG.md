# Changelog

## 0.2.1

- Stop replacing `gateway.controlUi.allowedOrigins` on every start. Origins added
  by hand or from the Control UI are now merged in and survive restarts.
- Leave `openclaw.json` completely untouched when the merged result is identical,
  instead of rewriting it on every boot and triggering a pointless hot reload.
- Keep the previous version as `openclaw.json.addon.bak` whenever a write does
  happen.

## 0.2.0

- Add a web terminal on the Home Assistant sidebar, served through Ingress with
  `ttyd` and `tmux`. `oc-maint` is now reachable without an SSH add-on, without
  Docker access and without an exposed port. Enabled by default via
  `enable_terminal`.
- Fix boolean options being impossible to turn off. jq's `//` operator falls back
  on `false` as well as `null`, so `enable_terminal: false` was read as unset and
  reverted to its default.
- The terminal is supervised separately from the gateway, so it stays reachable
  exactly when the gateway is broken.

## 0.1.4

- Add the opt-in `auto_approve_devices` option. Home Assistant's official
  Terminal & SSH add-on has no Docker access, so on such a setup there was no
  way at all to reach `oc-maint` and approve a Control UI browser. The
  supervisor can now approve pending pairing requests itself.
- Approved request ids are remembered so upgrade requests are not re-submitted
  in a loop.

## 0.1.3

- Set `HOME`, `XDG_CONFIG_HOME` and `PATH` as container environment variables.
  Previously they were only exported inside `run.sh`, so a `docker exec` session
  read `/root/.openclaw` instead of the live state and `openclaw` commands
  targeted the wrong install.
- Add `oc-maint devices` and `oc-maint approve <id>` for the Control UI browser
  pairing ceremony.

## 0.1.2

- Add the `allowed_origins` option. Without it the Control UI answers
  `origin not allowed` whenever the dashboard is opened by IP or hostname,
  because OpenClaw only trusts origins listed in
  `gateway.controlUi.allowedOrigins`.
- Loopback, `homeassistant` and `homeassistant.local` origins are now always
  allowed.

## 0.1.1

- Fix the build failing with `apt-get: not found`. The Supervisor overrides
  `ARG BUILD_FROM` with a Home Assistant Alpine base image, so the Dockerfile
  now pins `FROM node:24-bookworm-slim` explicitly and no longer relies on
  `BUILD_FROM`. `build.yaml` was removed for the same reason.

## 0.1.0

Initial release.

- Supervised OpenClaw gateway with restart backoff, health measured by the
  listening socket rather than an unreliable PID.
- `oc-maint` operator CLI with a real maintenance mode, so `openclaw doctor --fix`
  and updates can run with the gateway stopped.
- Config is merged into `openclaw.json`, never overwritten.
- Auth token generated automatically when binding beyond loopback.
- Persistent state, workspace and npm globals under `/config`.
