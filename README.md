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

## Folder access

The container sees none of your files until you pick them. When you choose a folder or file in the app's file dialog (GNOME's dialog, shown through the desktop portal), `grantd.py` mounts it into the running container at the same path before the app gets the answer.

- Only paths inside your home folder, `/run/media`, `/mnt` or `/media` are granted. Your home folder itself and the app's own `~/.config` and `~/.cache` are refused.
- Picked folders are remembered in `~/.local/share/claude-desktop-container/grants` and mounted again at the next start. Picked single files last until the app quits.
- Take one back with `./claude-desktop.sh --revoke ~/Projects/foo`. Processes already working inside it keep access until they exit.
- Dragged-in folders and typed paths aren't granted, only dialog picks.

`grantd.py` is started by `claude-desktop.sh` on a fresh launch, relays the app's session bus, runs `podman run` as its child and exits with it. If it's killed, the app loses its bus (sign-in, notifications, links) until you restart Claude.

## Files

| File | Purpose |
|------|---------|
| `Containerfile` | Debian 13 + Anthropic's apt repo + `claude-desktop`. Swaps in an `xdg-open` that opens links in your host browser through the desktop portal. |
| `claude-desktop.sh` | Starts the container through `grantd.py`, forwards links to a running one, or revokes a folder (`--revoke`). |
| `grantd.py` | Session-bus relay that mounts folders you pick in the file dialog into the running container. |
| `install.sh` | Builds the image and installs the host launcher entry, icon and `claude://` handler. |

Your settings and sign-in data live in `~/.local/share/claude-desktop-container/`, so they survive rebuilds: `home/` is the container's home folder (Claude Code's `~/.claude.json` and `~/.claude/`), with `config/` and `cache/` mounted over its `.config` and `.cache`. Folders you grant leave empty placeholder folders under `home/` (for example `home/Projects/foo`); the real files stay where they are.

## What the container can access

The app runs as your own user (not root), and the container gets only these from your session:

- the Wayland socket (display)
- the D-Bus session bus, relayed through `grantd.py` (keyring, opening links in your browser, desktop notifications)
- folders and files you pick in the file dialog (see Folder access)
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
