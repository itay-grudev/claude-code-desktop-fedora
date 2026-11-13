# Claude Desktop on Fedora (Podman + Debian)

Runs Anthropic's official Claude Desktop Linux beta, which ships only for Debian/Ubuntu, inside a rootless Podman container on Fedora, using Wayland directly.

Everything is installed from official sources: Debian's `debian:13` image and Anthropic's apt repo, following [code.claude.com/docs/en/desktop-linux](https://code.claude.com/docs/en/desktop-linux). The build fails if the repo signing key doesn't match the fingerprint Anthropic publishes (`31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`).

## Requirements

- Fedora with a Wayland session and PipeWire (the defaults)
- `podman`
- An unlocked desktop keyring (GNOME Keyring on Fedora Workstation), so the app can save your sign-in

## Install / update

```sh
./install.sh
```

This builds the image, adds **Claude** to the app grid, and registers it as the `claude://` link handler. The app doesn't update itself on Linux, so re-run `install.sh` to update; it rebuilds the image with the latest `claude-desktop` package.

## Run

Open **Claude** from the app grid, or run:

```sh
./claude-desktop.sh
```

If the app is already running, the script passes its arguments (for example a `claude://` sign-in link) to the open window instead of starting a second copy.

## Files

| File | Purpose |
|------|---------|
| `Containerfile` | Debian 13 + Anthropic's apt repo + `claude-desktop`. Swaps in an `xdg-open` that opens links in your host browser through the desktop portal. |
| `claude-desktop.sh` | Starts the container, or forwards links to the running one. |
| `install.sh` | Builds the image and installs the host launcher entry, icon and `claude://` handler. |

Your settings and sign-in data live in `~/.local/share/claude-desktop-container/` (the app's `~/.config` and `~/.cache`), so they survive rebuilds.

## What the container can access

The app runs as your own user (not root), and the container gets only these from your session:

- the Wayland socket (display)
- the D-Bus session bus (keyring, opening links in your browser, desktop notifications)
- the PulseAudio socket provided by PipeWire, plus `pipewire-0` (mic, speakers, screen sharing)
- `/dev/dri` (GPU)

The whole session bus is shared, so the app can reach any service on it, not only the ones above. SELinux labeling is disabled for this container (`label=disable`) so it can use the host sockets.

## Known limits

- Linux support is a beta from Anthropic. Computer Use and dictation aren't available on Linux yet.
- Cowork is left out: it needs KVM and a VM stack inside the container (the image skips the package's recommended QEMU packages).
- The Quick Entry hotkey on Wayland needs your desktop's GlobalShortcuts portal (not tested here).
- Terminal messages about "WebGL blocklisted" and the system bus are harmless.

## Uninstall

```sh
podman rmi localhost/claude-desktop
rm ~/.local/share/applications/com.anthropic.Claude.desktop
rm ~/.local/share/icons/hicolor/*/apps/claude-desktop.png
rm -r ~/.local/share/claude-desktop-container   # deletes your app settings and sign-in
```
