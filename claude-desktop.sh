#!/bin/sh
# Run Claude Desktop from the Debian container on the host Wayland session.
# If it's already running, hand the args (e.g. a claude:// sign-in link) to the running instance.
# Folders picked in the file chooser are mounted at their real path by grantd.py; see README.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
uid="$(id -u)"
run="/run/user/$uid"
data="${XDG_DATA_HOME:-$HOME/.local/share}/claude-desktop-container"
mkdir -p "$data/home" "$data/config" "$data/cache"

# Take back a folder picked earlier: claude-desktop.sh --revoke ~/Projects/foo  (the list is $data/grants)
if [ "${1:-}" = --revoke ]; then
  exec /usr/bin/python3 "$here/grantd.py" --revoke "$2" claude-desktop "$data/grants"
fi
if podman container exists claude-desktop 2>/dev/null; then
  exec podman exec claude-desktop claude-desktop --ozone-platform=wayland "$@"
fi

# grantd.py owns the bus socket the container gets, relays it to the real session bus,
# runs the container as its child and exits with it.
bus="$XDG_RUNTIME_DIR/claude-desktop-bus"
exec /usr/bin/python3 "$here/grantd.py" "$bus" claude-desktop "$data/grants" -- \
  podman run --rm --name claude-desktop \
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
  -v "$bus:$run/bus" \
  -e PULSE_SERVER="unix:$run/pulse/native" \
  -v "$XDG_RUNTIME_DIR/pulse/native:$run/pulse/native" \
  -v "$XDG_RUNTIME_DIR/pipewire-0:$run/pipewire-0" \
  -v "$data/home:$HOME" \
  -v "$data/config:$HOME/.config" \
  -v "$data/cache:$HOME/.cache" \
  localhost/claude-desktop "$@"
