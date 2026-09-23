// home/quickshell/.config/quickshell/bar/modules/Volume.qml
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../../theme"
import "../../services"

Item {
    id: root

    property bool compact: false
    property Item island: null
    property color island_color: Theme.bg_core

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink].filter(o => o)
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

    readonly property string glyph: {
        if (root.muted) return "";
        if (root.volume <= 0.33) return "";
        if (root.volume <= 0.66) return "";
        return "";
    }

    readonly property string tooltip_text: {
        if (!root.sink) return "No output device";
        const label = root.sink.description || root.sink.name;
        return label + " // " + Math.round(root.volume * 100) + "%";
    }

    Component.onCompleted: Popups.register_default("volume", root.island, root.island_color)

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: 4
        color: Theme.bg_surface
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    Row {
        id: row
        spacing: 6

        Text {
            text: root.glyph
            color: Theme.theme_primary
            opacity: root.muted ? 0.5 : 1
            font.family: Theme.font_family
            font.pixelSize: Theme.font_size
        }

        Text {
            visible: !root.compact
            text: Math.round(root.volume * 100) + "%"
            color: Theme.fg_core
            font.family: Theme.font_family
            font.pixelSize: Theme.font_size
        }
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, root.tooltip_text);
            else Tooltip.hide();
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted;
            } else {
                Popups.toggle("volume", root.island, root.island_color);
            }
        }
        onWheel: wheel => {
            if (!root.sink || !root.sink.ready || !root.sink.audio) return;
            const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
            root.sink.audio.volume = Math.max(0, Math.min(1, root.sink.audio.volume + step));
        }
    }
}
