// home/quickshell/.config/quickshell/services/ScreenShare.qml
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

// Tells Hyprland whether a portal screen share runs. xdg-desktop-portal-hyprland keeps one PipeWire node per share for as long as it lasts, which Hyprland's own screenshare.state event can't match: that goes false between frames of a static screen.
Scope {
    id: root

    // wf-recorder captures without the portal, so a recording counts as a share of its own.
    readonly property bool live: Screenshot.recording || Pipewire.nodes.values.some(n => n.name === "xdg-desktop-portal-hyprland")

    function send(on) {
        Hyprland.dispatch("ScreenShare.set_live(" + on + ")");
    }

    onLiveChanged: root.send(root.live)

    // A reload rebuilds Hyprland's rules and forgets the state; Hyprland ignores a repeat of true. No teardown on destruction: a Quickshell reload would land it after the new generation's resend, and a quit is cleaned up here on the next start.
    Component.onCompleted: root.send(root.live)

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded") root.send(root.live);
        }
    }
}
