# Build upstream Paperclip from a pinned ref.
FROM node:22-bookworm AS paperclip-build
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*
RUN corepack enable

ARG PAPERCLIP_REPO=https://github.com/paperclipai/paperclip.git
ARG PAPERCLIP_REF=v2026.416.0

WORKDIR /paperclip
RUN git clone --depth 1 --branch "${PAPERCLIP_REF}" "${PAPERCLIP_REPO}" .
RUN pnpm install --frozen-lockfile
RUN pnpm --filter @paperclipai/ui build
RUN pnpm --filter @paperclipai/plugin-sdk build
RUN pnpm --filter @paperclipai/server build
RUN test -f server/dist/index.js

# Runtime image (direct Paperclip server, no wrapper).
FROM node:22-bookworm
ENV NODE_ENV=production
ENV CLAUDE_CODE_BUBBLEWRAP=1
# Match upstream production image defaults (paperclipai/paperclip Dockerfile) so
# agent tooling, OpenCode, and config paths behave the same in containers.
ENV HOME=/paperclip \
    PAPERCLIP_HOME=/paperclip \
    CODEX_HOME=/data/.codex \
    PAPERCLIP_INSTANCE_ID=default \
    PAPERCLIP_CONFIG=/paperclip/instances/default/config.json \
    OPENCODE_ALLOW_ALL_MODELS=true

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    openssh-client \
    ripgrep \
    && mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*
RUN corepack enable

WORKDIR /app
COPY --from=paperclip-build /paperclip /app

WORKDIR /wrapper
COPY package.json /wrapper/package.json
RUN npm install --omit=dev && npm cache clean --force
COPY src /wrapper/src
COPY scripts/entrypoint.sh /wrapper/entrypoint.sh
COPY scripts/bootstrap-ceo.mjs /wrapper/template/bootstrap-ceo.mjs
RUN chmod +x /wrapper/entrypoint.sh

# Optional local adapters/tools parity with upstream Dockerfile.
RUN npm install --global --include=optional @openai/codex@latest
RUN npm install --global --omit=dev @anthropic-ai/claude-code@latest opencode-ai
RUN npm install --global --omit=dev tsx
# Cursor CLI for Paperclip `cursor` adapter (auth via CURSOR_API_KEY or agent login).
# Full package required (bundled node + JS chunks); do not copy cursor-agent alone.
ARG CURSOR_AGENT_VERSION=2026.05.16-0338208
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) CURSOR_ARCH=x64 ;; \
      arm64) CURSOR_ARCH=arm64 ;; \
      *) echo "Unsupported architecture for Cursor CLI" >&2; exit 1 ;; \
    esac; \
    mkdir -p /opt/cursor-agent; \
    curl -fSL "https://downloads.cursor.com/lab/${CURSOR_AGENT_VERSION}/linux/${CURSOR_ARCH}/agent-cli-package.tar.gz" \
      | tar -xzf - -C /opt/cursor-agent --strip-components=1; \
    test -x /opt/cursor-agent/cursor-agent; \
    ln -sf /opt/cursor-agent/cursor-agent /usr/local/bin/agent; \
    ln -sf /opt/cursor-agent/cursor-agent /usr/local/bin/cursor-agent
RUN mkdir -p /paperclip \
    && chown -R node:node /app /paperclip /wrapper

# Railway sets PORT at runtime and this process binds to it.
# Entrypoint runs as root, fixes /paperclip volume permissions, then execs as node.
EXPOSE 3100
ENTRYPOINT ["/wrapper/entrypoint.sh"]
CMD ["sh", "-c", "mkdir -p /data/.codex && node /wrapper/src/server.js"]
