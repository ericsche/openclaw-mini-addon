# Pinned explicitly, NOT via ARG BUILD_FROM.
# The Supervisor passes BUILD_FROM pointing at a Home Assistant Alpine base
# image, which would override any default we set here and break the build:
# Alpine has no apt-get. OpenClaw needs Node 24, so we start from it directly.
FROM node:24-bookworm-slim

# Supplied by the Supervisor from config.yaml. Locally built add-ons must carry
# the io.hass.* labels themselves; the Home Assistant builder action would
# otherwise inject them.
ARG BUILD_VERSION=0.1.3
ARG BUILD_ARCH=amd64

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false

# iproute2 -> ss (port ownership), procps -> pgrep/kill, jq -> options parsing.
# git/ripgrep/curl are the bare minimum most OpenClaw skills expect.
# tmux keeps the web terminal session alive when the browser tab is closed.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      jq \
      iproute2 \
      procps \
      ripgrep \
      tmux \
      tzdata \
 && rm -rf /var/lib/apt/lists/*

# ttyd is not packaged for Debian, so take the upstream static binary.
ARG TTYD_VERSION=1.7.7
RUN curl -fsSL -o /usr/local/bin/ttyd \
      "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64" \
 && chmod +x /usr/local/bin/ttyd \
 && ttyd --version

# Baked-in runtime so the first boot is fast and works offline.
# A later `oc-maint update` installs into /config/.node_global, which wins in PATH.
RUN npm install -g openclaw@latest \
 && npm cache clean --force

COPY oc-common.sh /usr/local/lib/oc-common.sh
COPY run.sh /usr/local/bin/run.sh
COPY oc-maint /usr/local/bin/oc-maint
RUN chmod +x /usr/local/bin/run.sh /usr/local/bin/oc-maint

# Declared AFTER the npm install above, so build-time caches stay out of /config
# (which is a mount at runtime and would shadow them anyway).
#
# These matter for `docker exec` sessions, not just for run.sh: OpenClaw derives
# its state directory from the account home, so without HOME=/config an exec'd
# `openclaw devices approve` would read /root/.openclaw and miss the live state.
ENV HOME=/config \
    XDG_CONFIG_HOME=/config \
    PATH=/config/.node_global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /config
CMD ["/usr/local/bin/run.sh"]

LABEL \
  io.hass.name="OpenClaw Mini" \
  io.hass.description="Minimal OpenClaw gateway add-on with a working maintenance mode" \
  io.hass.type="addon" \
  io.hass.version="${BUILD_VERSION}" \
  io.hass.arch="${BUILD_ARCH}" \
  org.opencontainers.image.title="OpenClaw Mini" \
  org.opencontainers.image.source="https://github.com/ericsche/openclaw-mini-addon" \
  org.opencontainers.image.licenses="MIT"
