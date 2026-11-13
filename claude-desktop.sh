#!/bin/sh
# Run Claude Desktop from the Debian container on the host Wayland session.
# If it's already running, hand the args (e.g. a claude:// sign-in link) to the running instance.
set -eu
if podman container exists claude-desktop 2>/dev/null; then
  exec podman exec claude-desktop claude-desktop --ozone-platform=wayland "$@"
fi

uid="$(id -u)"
run="/run/user/$uid"
data="${XDG_DATA_HOME:-$HOME/.local/share}/claude-desktop-container"
mkdir -p "$data/config" "$data/cache"

exec podman run --rm --name claude-desktop \
  --userns=keep-id \
  --security-opt label=disable \
  --device /dev/dri \
  --ipc=host \
  --mount type=tmpfs,dst="$run",tmpfs-mode=0700,U=true \
  -e HOME="$HOME" \
  -e WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
  -e XDG_RUNTIME_DIR="$run" \
  -e DBUS_SESSION_BUS_ADDRESS="unix:path=$run/bus" \
  -e XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-}" \
  -v "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY:$run/$WAYLAND_DISPLAY" \
  -v "$XDG_RUNTIME_DIR/bus:$run/bus" \
  -e PULSE_SERVER="unix:$run/pulse/native" \
  -v "$XDG_RUNTIME_DIR/pulse/native:$run/pulse/native" \
  -v "$XDG_RUNTIME_DIR/pipewire-0:$run/pipewire-0" \
  -v "$data/config:$HOME/.config" \
  -v "$data/cache:$HOME/.cache" \
  localhost/claude-desktop "$@"
