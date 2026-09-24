// home/quickshell/.config/quickshell/bar/modules/Volume.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "../../theme"
import "../../services"
import "../../components"

Item {
    id: root

    property bool compact: false
    property string screen_name: ""
    property Item island: null
    property color island_color: Theme.bg_core

    WheelStepper {
        id: wheel_stepper
    }

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

    onIslandChanged: if (root.island) Popups.register_default("volume", root.island, root.island_color, root.screen_name, root)
    Component.onDestruction: Popups.unregister("volume", root.screen_name, root)

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Style.bar_radius(4)
        color: Style.bar_hover_bg
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    RowLayout {
        id: row
        spacing: 6

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.glyph
            color: Theme.theme_primary
            opacity: root.muted ? 0.5 : 1
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Theme.glyph_size
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: !root.compact
            text: Math.round(root.volume * 100) + "%"
            color: Style.bar_fg
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
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
                Popups.toggle("volume", root.island, root.island_color, root.screen_name);
            }
        }
        onWheel: wheel => {
            if (!root.sink || !root.sink.ready || !root.sink.audio) return;
            const notches = wheel_stepper.consume(wheel.angleDelta.y || wheel.pixelDelta.y);
            if (notches === 0) return;
            const pct = wheel_stepper.snap_by(Math.round(root.sink.audio.volume * 100), notches, 0, 100);
            root.sink.audio.volume = pct / 100;
        }
    }
}
