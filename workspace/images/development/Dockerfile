# =============================================================================
# Workspace image — code-server + OpenCode on ONE filesystem, non-root
# =============================================================================
# Build (context MUST be workspace/, not this directory — the image bakes in
# the shared config files from opencode/config and code-server/config):
#   docker build -f workspace/images/development/Dockerfile workspace/
#
# Constraints (docs/architecture/security-model.md, ADR-0002/0006):
#   * runs as unprivileged user `coder` (uid/gid 1000)
#   * NO docker CLI, NO aws CLI — workspaces must never touch the host
#     docker socket or AWS credentials; AI access goes through LiteLLM only
#   * apps bind to container loopback; Coder's authenticated app proxy is
#     the only way in
#   * all persistent state lives under /home/coder (named volume)
# Versions pinned (verified against registry.npmjs.org + Docker Hub 2026-11-10):
#   code-server 4.145.2 (requires node >= 24), opencode-ai 1.19.5,
#   base node:24.22.2-bookworm
# =============================================================================

FROM node:24.22.2-bookworm

ARG CODE_SERVER_VERSION=4.145.2
ARG OPENCODE_VERSION=1.19.5

# --- developer toolchain -----------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq openssh-client procps less vim-tiny \
 && rm -rf /var/lib/apt/lists/*

# --- IDE + AI agent (npm, version-pinned) --------------------------------------
RUN npm install -g "code-server@${CODE_SERVER_VERSION}" "opencode-ai@${OPENCODE_VERSION}" \
 && npm cache clean --force

# --- non-root user --------------------------------------------------------------
RUN groupadd --gid 1000 coder \
 && useradd --create-home --uid 1000 --gid 1000 --shell /bin/bash coder

# --- service launcher (used by the Coder workspace startup script) --------------
COPY --chown=coder:coder images/development/start-workspace-services.sh /usr/local/bin/start-workspace-services.sh
RUN chmod 0755 /usr/local/bin/start-workspace-services.sh

# --- baked defaults (single source of truth for seeded configs) -----------------
# opencode.json: byte-identical to workspace/templates/standard/opencode.json
# (unit-tested); the workspace startup script seds __LITELLM_BASE_URL__ from it.
COPY opencode/config/opencode.json /opt/defaults/opencode.json
# code-server settings seeded once per volume at first start.
COPY code-server/config/default-settings.json /opt/defaults/code-server-settings.json
RUN chmod 0444 /opt/defaults/*.json

USER coder
WORKDIR /home/coder
ENV HOME=/home/coder \
    CODE_SERVER_BIND=127.0.0.1:8080 \
    OPENCODE_HOST=127.0.0.1 \
    OPENCODE_PORT=4096

# No ENTRYPOINT/CMD by design: the Coder agent is the container entrypoint
# (see workspace/templates/standard/). This image only provides binaries + user.
