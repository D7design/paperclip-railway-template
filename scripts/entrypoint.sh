#!/bin/sh
set -e

export PAPERCLIP_HOME="${PAPERCLIP_HOME:-/paperclip}"
export CODEX_HOME="${CODEX_HOME:-/paperclip/.codex}"

# When Railway mounts a volume at /paperclip it is often not writable by the node user.
# Create dirs Paperclip and Codex need and ensure the whole tree is owned by node.
mkdir -p "${PAPERCLIP_HOME}/instances/default/logs"
mkdir -p "${CODEX_HOME}"
chmod 700 "${CODEX_HOME}" 2>/dev/null || true
chown -R node:node "${PAPERCLIP_HOME}"

# ---------- Fix for GitHub issue #4 ----------
# Claude Code refuses --dangerously-skip-permissions when it detects
# root / sudo / elevated capabilities.  `gosu` drops uid/gid but keeps
# inherited Linux capabilities, which Claude Code interprets as elevated
# privilege.
#
# `setpriv` (util-linux, pre-installed on Debian Bookworm) lets us
# explicitly clear all inherited + ambient capabilities so the child
# process looks like a genuinely unprivileged user.
#
# We also unset any SUDO_* env vars that might leak from the container
# runtime, as Claude Code checks for those too.
unset SUDO_USER SUDO_UID SUDO_GID SUDO_COMMAND 2>/dev/null || true
 
exec setpriv \
  --reuid=node \
  --regid=node \
  --init-groups \
  --inh-caps=-all \
  "$@"
