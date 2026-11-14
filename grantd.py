#!/usr/bin/python3
"""Per-pick folder access for the Claude Desktop container.

Sits between the container and the host session bus. When the desktop portal's file
chooser answers the app, each picked path is bind-mounted into the running container
at the same path BEFORE the answer is passed on, so the app never sees a missing path.

  grantd.py SOCKET CONTAINER GRANTS_FILE -- podman run ...   proxy the bus, run the container, exit with it
  grantd.py --revoke PATH CONTAINER GRANTS_FILE              forget a folder, unmount it if the app is running
"""
import ctypes, os, subprocess, sys, urllib.parse

HOME = os.path.expanduser("~")
# Only paths inside these roots are ever mounted; anything else would let a pick shadow container system dirs.
ROOTS = os.environ.get("CLAUDE_GRANT_ROOTS", f"{HOME}:/run/media:/mnt:/media").split(":")
OWN = [f"{HOME}/.config", f"{HOME}/.cache"]  # the container's own mounts; never mount over or under them


def allowed(path):
    inside = lambda p, root: (p + "/").startswith(root.rstrip("/") + "/")
    return (os.path.isabs(path) and os.path.normpath(path) == path
            and any(inside(path, r) and path != r for r in ROOTS)
            and not any(inside(path, o) or inside(o, path) for o in OWN))


def libc(name, *args):
    r = getattr(ctypes.CDLL(None, use_errno=True), name)(*args)
    if r < 0:
        raise OSError(ctypes.get_errno(), f"{name}: {os.strerror(ctypes.get_errno())}")
    return r


def in_container(op, pid, path):
    """Runs under `podman unshare`: root in podman's user namespace, host files visible."""
    same = lambda a, b: (a.st_dev, a.st_ino) == (b.st_dev, b.st_ino)
    if op == "mount":
        if not os.path.lexists(path):
            open(path, "x").close()  # a Save dialog picked a new file: it needs to exist to be mounted
        host, isdir = os.stat(path), os.path.isdir(path)
        # Take a detached copy of the host folder's mount while the host is still visible...
        tree = libc("open_tree", -100, path.encode(), 1 | 0x8000 | os.O_CLOEXEC)  # OPEN_TREE_CLONE | AT_RECURSIVE
    os.setns(os.open(f"/proc/{pid}/ns/mnt", os.O_RDONLY), os.CLONE_NEWNS)  # ...step into the container...
    if op == "umount":
        return libc("umount2", path.encode(), 2)  # MNT_DETACH
    if os.path.exists(path) and same(os.stat(path), host):
        return  # already granted (itself or a parent folder)
    os.makedirs(path if isdir else os.path.dirname(path), exist_ok=True)
    if not isdir:
        open(path, "a").close()
    libc("move_mount", tree, b"", -100, path.encode(), 4)  # ...and attach it at the same path (MOVE_MOUNT_F_EMPTY_PATH)


def helper(op, container, path):
    pid = subprocess.run(["podman", "inspect", "-f", "{{.State.Pid}}", container],
                         capture_output=True, text=True).stdout.strip()
    return pid not in ("", "0") and subprocess.run(
        ["podman", "unshare", sys.executable, __file__, "--" + op, pid, path]).returncode == 0


def read_grants(grants_file):
    return open(grants_file).read().splitlines() if os.path.exists(grants_file) else []


def grant(container, grants_file, path):
    if not path or not allowed(path):
        return print(f"grantd: not granting {path!r} (only folders inside {ROOTS}, and not the home folder itself)", file=sys.stderr)
    if helper("mount", container, path) and os.path.isdir(path) and path not in read_grants(grants_file):
        with open(grants_file, "a") as f:  # folders are remembered; single files last until the app quits
            f.write(path + "\n")


def revoke(path, container, grants_file):
    path = os.path.abspath(path)
    keep = [g for g in read_grants(grants_file) if g != path]
    with open(grants_file, "w") as f:
        f.writelines(g + "\n" for g in keep)
    helper("umount", container, path)


def serve(sock, container, grants_file, cmd):
    from gi.repository import Gio, GLib
    upstream = Gio.dbus_address_get_for_bus_sync(Gio.BusType.SESSION, None)
    portal, links = {}, set()
    # Only a Response sent by the real portal counts; the bus stamps the sender, so the app can't fake one.
    Gio.bus_watch_name(Gio.BusType.SESSION, "org.freedesktop.portal.Desktop", Gio.BusNameWatcherFlags.NONE,
                       lambda c, name, owner: portal.update(owner=owner), lambda c, name: portal.clear())

    def from_bus(msg):
        if (msg.get_message_type() == Gio.DBusMessageType.SIGNAL and msg.get_member() == "Response"
                and msg.get_interface() == "org.freedesktop.portal.Request" and msg.get_signature() == "ua{sv}"
                and msg.get_sender() == portal.get("owner")):
            code, results = msg.get_body().unpack()
            for uri in results.get("uris", []) if code == 0 else []:
                # No Gio calls in here: this runs on GDBus's worker thread, and anything that talks D-Bus would deadlock.
                if uri.startswith("file:///"):
                    grant(container, grants_file, urllib.parse.unquote(uri[7:]))  # blocks this bus->app stream

    def relay(dst, hook=None):
        def on_message(conn, msg, incoming, *_):
            if not incoming:
                return msg
            try:
                if hook:
                    hook(msg)
            except Exception as e:  # a failed grant must never break the app's bus connection
                print(f"grantd: {e!r}", file=sys.stderr)
            try:
                dst.send_message(msg, Gio.DBusSendMessageFlags.PRESERVE_SERIAL)
            except GLib.Error:
                pass  # other side already closed
            return None
        return on_message

    def on_new(server, app):
        F = Gio.DBusConnectionFlags
        bus = Gio.DBusConnection.new_for_address_sync(
            upstream, F.AUTHENTICATION_CLIENT | F.DELAY_MESSAGE_PROCESSING, None, None)
        app.add_filter(relay(bus))
        bus.add_filter(relay(app, from_bus))
        link = (app, bus)
        links.add(link)

        def closed(*_):
            links.discard(link)
            for c in link:
                if not c.is_closed():
                    c.close(None, None)
        app.connect("closed", closed)
        bus.connect("closed", closed)
        bus.start_message_processing()
        return True

    if os.path.exists(sock):
        os.unlink(sock)
    server = Gio.DBusServer.new_sync(f"unix:path={sock}", Gio.DBusServerFlags.AUTHENTICATION_REQUIRE_SAME_USER,
                                     Gio.dbus_generate_guid(), None, None)
    server.connect("new-connection", on_new)
    server.start()
    import threading
    threading.Thread(target=GLib.MainLoop().run, daemon=True).start()

    # Remembered folders are mounted the ordinary way at start.
    # shortcut: -v can't take a path containing ':'; such folders must be re-picked each start. Switch to --mount if it matters.
    i = cmd.index("run") + 1
    cmd[i:i] = [a for g in read_grants(grants_file) if allowed(g) and os.path.isdir(g) and ":" not in g
                for a in ("-v", f"{g}:{g}")]
    try:
        return subprocess.call(cmd)
    finally:
        os.unlink(sock)


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0] in ("--mount", "--umount"):
        in_container(a[0][2:], a[1], a[2])
    elif a[0] == "--revoke":
        revoke(*a[1:4])
    elif a[0] == "--selftest":
        assert allowed(f"{HOME}/Projects/x") and allowed("/run/media/u/disk/x")
        for bad in (HOME, "/", "/usr/lib", f"{HOME}/.config", f"{HOME}/.config/Claude", f"{HOME}/../etc", "relative", HOME + "x"):
            assert not allowed(bad), bad
        print("ok")
    else:
        sys.exit(serve(a[0], a[1], a[2], a[a.index("--") + 1:]))
