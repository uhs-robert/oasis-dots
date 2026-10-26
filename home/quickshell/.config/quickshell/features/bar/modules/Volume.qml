import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.theme
import qs.ui
import qs.features.bar

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

    readonly property string level_variant: root.muted ? "muted" : root.volume <= 0.33 ? "low" : root.volume <= 0.66 ? "mid" : "high"

    tooltip_text: {
        if (!root.sink) return "No output device";
        const label = root.sink.description || root.sink.name;
        return label + " // " + Math.round(root.volume * 100) + "%";
    }

    ModuleRow {
        id: row
        vertical: root.vertical
        spacing: root.vertical ? 2 : 6

        BarIcon {
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            name: "volume"
            fixed_slot: true
            variant: root.level_variant
            glyph: root.glyph
            tint: Theme.theme_primary
            opacity: root.muted ? 0.5 : 1
        }

        VerticalText {
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            visible: !root.compact
            vertical: root.vertical
            cross: root.cross
            full_text: Math.round(root.volume * 100) + "%"
            short_text: Math.round(root.volume * 100) + ""
            full_template: "100%"
            short_template: "100"
            color: Style.bar_fg
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
            const current = Math.round(root.sink.audio.volume * 100);
            const pct = wheel_stepper.step_level(wheel, null, current, 0, 100);
            if (pct !== current) root.sink.audio.volume = pct / 100;
        }
    }
}
