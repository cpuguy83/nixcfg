#!/usr/bin/env python3
"""Minimal org.freedesktop.FileManager1 implementation.

Owns the well-known name so desktop apps' "show in files" / "reveal in file
manager" actions (which call ShowItems/ShowFolders over D-Bus) succeed on a
setup that only uses a terminal file manager (yazi).

For each request the first usable file:// URI is converted to a local path and
handed to a launcher program (argv[1]) which opens it in yazi. The process
idle-exits after a period of inactivity so it plays nicely with D-Bus
activation.
"""

import subprocess
import sys
from urllib.parse import unquote, urlparse

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

BUS_NAME = "org.freedesktop.FileManager1"
OBJECT_PATH = "/org/freedesktop/FileManager1"
IFACE = "org.freedesktop.FileManager1"

# Quit after this many seconds without a request.
IDLE_TIMEOUT_SECONDS = 30


def uri_to_path(uri):
    parsed = urlparse(uri)
    if parsed.scheme not in ("", "file"):
        return None
    if parsed.netloc not in ("", "localhost"):
        return None
    return unquote(parsed.path) or None


def first_path(uris):
    for uri in uris:
        path = uri_to_path(str(uri))
        if path:
            return path
    return None


class FileManager1(dbus.service.Object):
    def __init__(self, bus, loop, launcher):
        super().__init__(bus, OBJECT_PATH)
        self._loop = loop
        self._launcher = launcher
        self._idle_source = None
        self._reset_idle_timer()

    def _reset_idle_timer(self):
        if self._idle_source is not None:
            GLib.source_remove(self._idle_source)
        self._idle_source = GLib.timeout_add_seconds(
            IDLE_TIMEOUT_SECONDS, self._quit
        )

    def _quit(self):
        self._loop.quit()
        return False

    def _reveal(self, uris):
        self._reset_idle_timer()
        path = first_path(uris)
        if path is None:
            return
        try:
            subprocess.Popen(
                [self._launcher, path],
                start_new_session=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError as exc:
            sys.stderr.write("filemanager1: launch failed: %s\n" % exc)

    @dbus.service.method(IFACE, in_signature="ass", out_signature="")
    def ShowFolders(self, uris, startup_id):
        self._reveal(uris)

    @dbus.service.method(IFACE, in_signature="ass", out_signature="")
    def ShowItems(self, uris, startup_id):
        self._reveal(uris)

    @dbus.service.method(IFACE, in_signature="ass", out_signature="")
    def ShowItemProperties(self, uris, startup_id):
        self._reveal(uris)


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: filemanager1 <launcher>\n")
        return 2
    launcher = sys.argv[1]

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()

    request = bus.request_name(BUS_NAME, dbus.bus.NAME_FLAG_DO_NOT_QUEUE)
    if request not in (
        dbus.bus.REQUEST_NAME_REPLY_PRIMARY_OWNER,
        dbus.bus.REQUEST_NAME_REPLY_ALREADY_OWNER,
    ):
        # Another file manager already owns the name; nothing to do.
        return 0

    loop = GLib.MainLoop()
    FileManager1(bus, loop, launcher)
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
