// home/quickshell/.config/quickshell/bar/modules/Volume.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "../../theme"
import "../../services"
import "../../components"

BarModule {
    id: root
    module_name: "volume"

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

    tooltip_text: {
        if (!root.sink) return "No output device";
        const label = root.sink.description || root.sink.name;
        return label + " // " + Math.round(root.volume * 100) + "%";
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
            font.pixelSize: Style.bar_glyph_size
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: !root.compact
            text: Math.round(root.volume * 100) + "%"
            color: Style.bar_fg
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_font_size
            font.capitalization: Style.bar_capitalization
            font.letterSpacing: Style.bar_letter_spacing
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted;
            } else {
                root.toggle_popup();
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
