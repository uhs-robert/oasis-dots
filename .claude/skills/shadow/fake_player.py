#!/usr/bin/env python3
"""A fake MPRIS media player for the shadow bar.

Owns org.mpris.MediaPlayer2.shadowfake on the session bus named by DBUS_SESSION_BUS_ADDRESS, so Quickshell's
Mpris.players fills and the media popup has a track to draw. Only shadow.sh starts it, with the shadow's private bus.
"""

import argparse
import os
import signal
import sys
import time

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402 - the version call above must come first

BUS_NAME = "org.mpris.MediaPlayer2.shadowfake"
OBJECT_PATH = "/org/mpris/MediaPlayer2"

INTROSPECTION = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg type="x" direction="in"/></method>
    <method name="SetPosition"><arg type="o" direction="in"/><arg type="x" direction="in"/></method>
    <method name="OpenUri"><arg type="s" direction="in"/></method>
    <signal name="Seeked"><arg type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""

ROOT_IFACE = "org.mpris.MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
US_PER_S = 1_000_000


class FakePlayer:
    def __init__(self, title, artist, art_url, length_s):
        self.title = title
        self.artist = artist
        self.art_url = art_url
        self.length_us = int(length_s * US_PER_S)
        self.playing = True
        # Position is the base plus the time since started_at, so nothing needs a timer.
        self.base_us = 0
        self.started_at = time.monotonic()
        self.connection = None

    def position_us(self):
        if not self.playing:
            return self.base_us
        elapsed = int((time.monotonic() - self.started_at) * US_PER_S)
        return (self.base_us + elapsed) % self.length_us

    def set_position(self, us):
        self.base_us = max(0, min(us, self.length_us))
        self.started_at = time.monotonic()

    def metadata(self):
        data = {
            "mpris:trackid": GLib.Variant("o", "/org/shadowfake/track/1"),
            "mpris:length": GLib.Variant("x", self.length_us),
            "xesam:title": GLib.Variant("s", self.title),
            "xesam:album": GLib.Variant("s", "Shadow Album"),
        }
        if self.artist:
            data["xesam:artist"] = GLib.Variant("as", [self.artist])
        if self.art_url:
            data["mpris:artUrl"] = GLib.Variant("s", self.art_url)
        return data

    def properties(self):
        return {
            (ROOT_IFACE, "CanQuit"): GLib.Variant("b", False),
            (ROOT_IFACE, "CanRaise"): GLib.Variant("b", False),
            (ROOT_IFACE, "HasTrackList"): GLib.Variant("b", False),
            (ROOT_IFACE, "Identity"): GLib.Variant("s", "Shadow Player"),
            (ROOT_IFACE, "SupportedUriSchemes"): GLib.Variant("as", []),
            (ROOT_IFACE, "SupportedMimeTypes"): GLib.Variant("as", []),
            (PLAYER_IFACE, "PlaybackStatus"): GLib.Variant(
                "s", "Playing" if self.playing else "Paused"
            ),
            (PLAYER_IFACE, "Rate"): GLib.Variant("d", 1.0),
            (PLAYER_IFACE, "Metadata"): GLib.Variant("a{sv}", self.metadata()),
            (PLAYER_IFACE, "Volume"): GLib.Variant("d", 1.0),
            (PLAYER_IFACE, "Position"): GLib.Variant("x", self.position_us()),
            (PLAYER_IFACE, "MinimumRate"): GLib.Variant("d", 1.0),
            (PLAYER_IFACE, "MaximumRate"): GLib.Variant("d", 1.0),
            (PLAYER_IFACE, "CanGoNext"): GLib.Variant("b", True),
            (PLAYER_IFACE, "CanGoPrevious"): GLib.Variant("b", True),
            (PLAYER_IFACE, "CanPlay"): GLib.Variant("b", True),
            (PLAYER_IFACE, "CanPause"): GLib.Variant("b", True),
            (PLAYER_IFACE, "CanSeek"): GLib.Variant("b", True),
            (PLAYER_IFACE, "CanControl"): GLib.Variant("b", True),
        }

    def get_property(self, _conn, _sender, _path, interface, name):
        return self.properties().get((interface, name))

    def set_property(self, *_args):
        return True

    def announce_status(self):
        changed = {
            "PlaybackStatus": self.properties()[(PLAYER_IFACE, "PlaybackStatus")]
        }
        self.connection.emit_signal(
            None,
            OBJECT_PATH,
            "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            GLib.Variant("(sa{sv}as)", (PLAYER_IFACE, changed, [])),
        )

    def play_pause(self, playing):
        if playing == self.playing:
            return
        self.base_us = self.position_us()
        self.started_at = time.monotonic()
        self.playing = playing
        self.announce_status()

    def seeked(self):
        self.connection.emit_signal(
            None,
            OBJECT_PATH,
            PLAYER_IFACE,
            "Seeked",
            GLib.Variant("(x)", (self.position_us(),)),
        )

    def method_call(self, _conn, _sender, _path, interface, method, params, invocation):
        if interface == PLAYER_IFACE:
            if method == "Play":
                self.play_pause(True)
            elif method in ("Pause", "Stop"):
                self.play_pause(False)
            elif method == "PlayPause":
                self.play_pause(not self.playing)
            elif method in ("Next", "Previous"):
                self.set_position(0)
                self.seeked()
            elif method == "Seek":
                self.set_position(self.position_us() + params.unpack()[0])
                self.seeked()
            elif method == "SetPosition":
                self.set_position(params.unpack()[1])
                self.seeked()
        invocation.return_value(None)


def main():
    parser = argparse.ArgumentParser(description="Fake MPRIS player for the shadow bar")
    parser.add_argument("--title", default="Shadow Track")
    parser.add_argument(
        "--artist", default="Shadow Artist", help="empty for a track with no artist"
    )
    parser.add_argument("--art-url", default="")
    parser.add_argument(
        "--length", type=float, default=180.0, help="track length in seconds"
    )
    args = parser.parse_args()

    # The one thing this script must never do is publish on the owner's session bus.
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    bus = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")
    if (
        not runtime
        or os.path.realpath(runtime).startswith("/run/user/")
        or bus != f"unix:path={runtime}/bus"
    ):
        sys.exit(
            f"fake_player: refusing bus '{bus}' outside a private runtime dir ('{runtime}')"
        )

    player = FakePlayer(args.title, args.artist, args.art_url, args.length)
    loop = GLib.MainLoop()
    node = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION)

    def on_bus_acquired(connection, _name):
        player.connection = connection
        for info in node.interfaces:
            connection.register_object(
                OBJECT_PATH,
                info,
                player.method_call,
                player.get_property,
                player.set_property,
            )

    def on_name_lost(_connection, _name):
        loop.quit()

    Gio.bus_own_name(
        Gio.BusType.SESSION,
        BUS_NAME,
        Gio.BusNameOwnerFlags.DO_NOT_QUEUE,
        on_bus_acquired,
        None,
        on_name_lost,
    )
    for sig in (signal.SIGTERM, signal.SIGINT):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, loop.quit)
    loop.run()


if __name__ == "__main__":
    main()
