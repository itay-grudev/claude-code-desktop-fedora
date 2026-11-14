#!/bin/sh
# Build the image and add "Claude" to the host app launcher, registered as the claude:// handler.
# Re-run to update: it rebuilds only when Anthropic's apt repo has a newer claude-desktop.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
img=localhost/claude-desktop

latest= old=
if podman image exists "$img"; then
  old="$(podman image inspect -f '{{.Id}}' "$img")"
  # Ask apt inside the current image: signed repo, and Debian's own version ordering.
  latest="$(podman run --rm --entrypoint sh "$img" -c 'apt-get update -qq >/dev/null && apt-cache policy claude-desktop' | awk '/Candidate:/{print $2}')"
  case "$latest" in ''|*[!0-9A-Za-z.+~:-]*) echo "Unexpected version from apt: '$latest'" >&2; exit 1 ;; esac
fi
# Always build: pinned to $latest, the cache makes it a no-op unless the version, base image or Containerfile changed.
podman build -q --pull=newer --build-arg CLAUDE_VERSION="$latest" -t claude-desktop "$here" >/dev/null
version="$(podman run --rm --entrypoint dpkg-query "$img" -W -f '${Version}' claude-desktop)"
if [ "$(podman image inspect -f '{{.Id}}' "$img")" = "$old" ]; then
  echo "Claude Desktop $version is up to date."
else
  echo "Built Claude Desktop $version."
  # Remove this project's replaced images; one still used by a running app stays until the next update.
  podman image prune -f --filter label=local.claude-desktop-container >/dev/null || true
  if podman container exists claude-desktop; then echo "Restart Claude to use it."; fi
  [ -z "$old" ] || notify-send -i claude-desktop "Claude Desktop image updated ($version)" "Restart Claude to use it." 2>/dev/null || true
fi

apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
mkdir -p "$apps" "$icons"

# Reuse the package's own desktop entry and icons; only point Exec at the wrapper.
c="$(podman create "$img")"
podman cp "$c:/usr/share/applications/com.anthropic.Claude.desktop" "$apps/"
for s in 16 32 48 128 256; do
  mkdir -p "$icons/hicolor/${s}x${s}/apps"
  podman cp "$c:/usr/share/icons/hicolor/${s}x${s}/apps/claude-desktop.png" "$icons/hicolor/${s}x${s}/apps/" 2>/dev/null || true
done
podman rm "$c" >/dev/null
sed -i "s|^Exec=claude-desktop|Exec=$here/claude-desktop.sh|" "$apps/com.anthropic.Claude.desktop"

update-desktop-database "$apps" 2>/dev/null || true
xdg-mime default com.anthropic.Claude.desktop x-scheme-handler/claude

# Daily update check: a systemd user timer that runs this script.
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$units"
cat > "$units/claude-desktop-update.service" <<EOF
[Unit]
Description=Update the Claude Desktop container image
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=$here/install.sh
EOF
cat > "$units/claude-desktop-update.timer" <<EOF
[Unit]
Description=Daily Claude Desktop update check

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now claude-desktop-update.timer >/dev/null 2>&1

echo "Installed. Launch 'Claude' from the app grid or run $here/claude-desktop.sh"
