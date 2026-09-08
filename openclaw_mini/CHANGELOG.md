# Changelog

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
