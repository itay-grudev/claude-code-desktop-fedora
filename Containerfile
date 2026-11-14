# Claude Desktop (official Linux beta) on Debian, per https://code.claude.com/docs/en/desktop-linux
FROM docker.io/library/debian:13
# Lets install.sh find and prune this project's old images, and nobody else's.
LABEL local.claude-desktop-container=1
# Set by install.sh to the version to install; a new value re-runs the step below, the same value reuses the cache.
ARG CLAUDE_VERSION=

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc https://downloads.claude.ai/claude-desktop/key.asc \
 # fail the build unless the key is exactly the fingerprint Anthropic documents
 && gpg --show-keys --with-colons /usr/share/keyrings/claude-desktop-archive-keyring.asc | awk -F: '$1=="fpr"{print $10}' \
    | grep -qx 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE \
 && echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
    > /etc/apt/sources.list.d/claude-desktop.list \
 && apt-get update \
 # --no-install-recommends skips the Cowork VM stack (qemu/ovmf); GL/fonts for Electron; gdbus for the xdg-open shim
 && apt-get install -y --no-install-recommends "claude-desktop${CLAUDE_VERSION:+=$CLAUDE_VERSION}" libgl1 libegl1 mesa-vulkan-drivers fonts-dejavu-core libglib2.0-bin \
 && rm -rf /var/lib/apt/lists/*

# Links (sign-in, docs) open in the host browser via the desktop portal on the shared session bus.
RUN printf '%s\n' '#!/bin/sh' \
    'exec gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.OpenURI.OpenURI "" "$1" "{}" >/dev/null' \
    > /usr/local/bin/xdg-open && chmod +x /usr/local/bin/xdg-open

ENTRYPOINT ["claude-desktop", "--ozone-platform=wayland"]
