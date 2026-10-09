// home/quickshell/.config/quickshell/services/ScreenShare.qml
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

// Tells Hyprland whether a portal screen share runs. xdg-desktop-portal-hyprland keeps one PipeWire node per share for as long as it lasts, which Hyprland's own screenshare.state event can't match: that goes false between frames of a static screen.
Scope {
    id: root

    readonly property bool live: Pipewire.nodes.values.some(n => n.name === "xdg-desktop-portal-hyprland")

    function send(on) {
        Hyprland.dispatch("ScreenShare.set_live(" + on + ")");
    }

    onLiveChanged: root.send(root.live)

    // A reload rebuilds Hyprland's rules and forgets the state; Hyprland ignores a repeat of what it has.
    Component.onCompleted: root.send(root.live)

    // Detached because the Hyprland socket may be gone by the time teardown runs. Leaving the share's rules on after the shell quits would stick until the next reload.
    Component.onDestruction: Quickshell.execDetached(["hyprctl", "dispatch", "ScreenShare.set_live(false)"])

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded") root.send(root.live);
        }
    }
}
