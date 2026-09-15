# Copilot instructions

## Build and test

- Build the add-on image from the add-on directory, not the repository root:

  ```bash
  VERSION="$(sed -n 's/^version: "\(.*\)"/\1/p' openclaw_mini/config.yaml)"
  docker build \
    --build-arg BUILD_VERSION="$VERSION" \
    --build-arg BUILD_ARCH=amd64 \
    -t openclaw-mini:dev \
    ./openclaw_mini
  ```

- Run the complete stubbed integration suite:

  ```bash
  ./tests/run-all.sh ./openclaw_mini
  ```

- Run one harness directly when working on a specific behavior:

  ```bash
  ./tests/test-supervisor.sh ./openclaw_mini
  ./tests/test-failure-path.sh ./openclaw_mini
  ./tests/test-terminal.sh ./openclaw_mini
  ./tests/test-auto-approve.sh ./openclaw_mini
  ./tests/test-config-persistence.sh ./openclaw_mini
  ```

  The tests require Bash, `jq`, `sed`, `grep`, and `seq`; they replace OpenClaw, `ss`, `pgrep`, `npm`, and `ttyd` with local stubs and do not require a container or OpenClaw installation.

## Architecture

- This repository is a Home Assistant add-on repository. `repository.yaml` describes the repository; `openclaw_mini/config.yaml` is the add-on manifest and defines the supported architecture, Ingress, port mapping, persistent mappings, options, and schemas. User-facing option text lives in `openclaw_mini/translations/en.yaml`, while `README.md` and `openclaw_mini/DOCS.md` document installation and operation.
- The image is intentionally based directly on `node:24-bookworm-slim`. Do not reintroduce `ARG BUILD_FROM`: Home Assistant supplies an Alpine `BUILD_FROM`, but this image needs Debian tooling and Node 24.
- `openclaw_mini/run.sh` is both the container entrypoint and the long-running supervisor. It reads `/data/options.json`, prepares persistent state, merges required gateway settings into OpenClaw's config, starts the independently supervised Ingress terminal, starts/restarts the gateway with bounded backoff, and optionally approves browser pairing requests.
- `openclaw_mini/oc-maint` is the operator CLI. It coordinates with `run.sh` through `/tmp/openclaw.maintenance`, allowing the gateway to remain stopped while `doctor` or an npm update owns OpenClaw's state lock. `openclaw_mini/oc-common.sh` contains the shared paths, environment setup, socket health check, and PID lookup used by both scripts.
- `oc-maint config` edits the live JSON through the Ingress terminal. It must retain the pre-edit backup and restore it whenever JSON validation fails.
- The listening socket is the source of truth for gateway health and process ownership. `openclaw gateway run` may fork, so its wrapper PID or successful exit does not prove that the gateway is healthy.
- Persistent runtime data belongs under `/config`: `.openclaw` for OpenClaw state/config, `clawd` for the workspace, and `.node_global` for npm globals that must survive image rebuilds. The terminal is served by `ttyd` on Ingress port 8099 and must remain available even when the gateway is stopped or failing.

## Repository-specific conventions

- Keep shell scripts as Bash with `set -euo pipefail` for runtime scripts. Supervisor loops and test harnesses deliberately use more selective error handling where expected failures must be observed instead of terminating the process.
- Read boolean add-on options with an explicit null check. In jq, `//` treats both `null` and `false` as fallback values, which would make an explicit `false` revert to the default.
- Treat `/config/.openclaw/openclaw.json` as user-owned. The add-on may enforce only the settings it needs: `gateway.mode`, `gateway.port`, `gateway.bind`, token auth when required, and the union of allowed Control UI origins. Preserve agents, channels, credentials, models, sessions, and unrelated gateway/control UI keys.
- A newly created config starts with `tools.profile: "minimal"` and `tools.alsoAllow: ["group:web"]` to limit schema overhead for local models. This is initialization only; never overwrite or migrate an existing `tools` object.
- Configuration updates must remain idempotent: compare the merged result with the existing file, do not rewrite an unchanged file, and keep the previous file as `openclaw.json.addon.bak` before a real change. Never replace `gateway.controlUi.allowedOrigins`; union add-on origins with existing values.
- Set `HOME=/config`, `XDG_CONFIG_HOME=/config`, the persistent npm prefix in `PATH`, and `OPENCLAW_SUPERVISOR_MODE=external`. The supervisor marker tells OpenClaw to defer gateway lifecycle and Doctor service repair to this add-on. Do not export `OPENCLAW_HOME`, `OPENCLAW_STATE_DIR`, `OPENCLAW_CONFIG_PATH`, or `OPENCLAW_WORKSPACE_DIR`; OpenClaw interprets those as isolated state.
- Keep maintenance operations routed through `oc-maint`. Do not use `openclaw update` or OpenClaw's gateway service commands in the container; there is no systemd, and update/doctor must run while the supervisor is paused.
- Control UI self-update is intentionally unavailable: a live gateway cannot perform OpenClaw's managed-service handoff without a native service. `managed-service-handoff-unavailable` and `external-supervisor-update-required` both mean the operator must run `oc-maint update`.
- Changes to an add-on option normally require synchronized updates to `config.yaml` defaults/schema, `translations/en.yaml`, both user-facing documentation files, option parsing in `run.sh`, and the relevant stubbed integration test.
- Preserve executable bits on `run.sh`, `oc-maint`, and all `tests/*.sh` files. The repository enforces LF endings through `.gitattributes`, including on Windows.
- When changing behavior, extend the existing black-box harness that owns it rather than testing copied shell functions in isolation. Harnesses sandbox the real scripts by rewriting `/usr/local/lib/oc-common.sh`, `/data/options.json`, and `/config`, then assert observable files, sockets, logs, and exit behavior.
- Release versions and release notes are maintained in `openclaw_mini/config.yaml` and `openclaw_mini/CHANGELOG.md`.
