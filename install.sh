#!/bin/sh
# Build the image and add "Claude" to the host app launcher, registered as the claude:// handler.
# Re-run to update (pulls the latest claude-desktop from Anthropic's apt repo).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
podman build --pull=newer --no-cache -t claude-desktop "$here"

apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
mkdir -p "$apps" "$icons"

# Reuse the package's own desktop entry and icons; only point Exec at the wrapper.
c="$(podman create localhost/claude-desktop)"
podman cp "$c:/usr/share/applications/com.anthropic.Claude.desktop" "$apps/"
for s in 16 32 48 128 256; do
  mkdir -p "$icons/hicolor/${s}x${s}/apps"
  podman cp "$c:/usr/share/icons/hicolor/${s}x${s}/apps/claude-desktop.png" "$icons/hicolor/${s}x${s}/apps/" 2>/dev/null || true
done
podman rm "$c" >/dev/null
sed -i "s|^Exec=claude-desktop|Exec=$here/claude-desktop.sh|" "$apps/com.anthropic.Claude.desktop"

update-desktop-database "$apps" 2>/dev/null || true
xdg-mime default com.anthropic.Claude.desktop x-scheme-handler/claude
echo "Installed. Launch 'Claude' from the app grid or run $here/claude-desktop.sh"
