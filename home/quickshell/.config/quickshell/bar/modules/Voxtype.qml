// home/quickshell/.config/quickshell/bar/modules/Voxtype.qml
import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../theme"
import "../../services"
import "../../components/bar_icons"

BarModule {
    id: root
    module_name: "voxtype"
    has_popup: false
    tooltip_text: VoxSession.active && VoxSession.exit_hint !== "" ? VoxSession.exit_hint : VoxtypeState.tooltip

    readonly property var glyphs: ({ idle: "", stopped: "" })
    readonly property color glyph_color: VoxtypeState.recording ? Theme.theme_label : VoxtypeState.transcribing ? Theme.warning : VoxtypeState.state === "stopped" ? Theme.fg_dim : Theme.theme_primary

    shown: VoxtypeState.installed
    implicitWidth: shown ? glyph.implicitWidth : 0
    implicitHeight: glyph.implicitHeight

    BarIcon {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        name: "voxtype"
        variant: VoxtypeState.state === "stopped" ? "stopped" : "idle"
        glyph: VoxtypeState.state === "stopped" ? root.glyphs.stopped : root.glyphs.idle
        tint: root.glyph_color

        SequentialAnimation {
            id: pulse_animation
            running: VoxtypeState.recording && Power.on_ac
            loops: Animation.Infinite
            onRunningChanged: if (!running) glyph.opacity = 1

            NumberAnimation { target: glyph; property: "opacity"; from: 1; to: 0.5; duration: 500; easing.type: Easing.InOutQuad }
            NumberAnimation { target: glyph; property: "opacity"; from: 0.5; to: 1; duration: 500; easing.type: Easing.InOutQuad }
        }
    }

    Shape {
        id: ring
        readonly property real diameter: glyph.implicitHeight + 2
        anchors.centerIn: glyph
        width: diameter
        height: diameter
        visible: VoxtypeState.transcribing
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.glyph_color
            strokeWidth: 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: ring.diameter / 2
                centerY: ring.diameter / 2
                radiusX: ring.diameter / 2 - 1
                radiusY: ring.diameter / 2 - 1
                startAngle: 0
                sweepAngle: 100
            }
        }

        RotationAnimation on rotation {
            running: ring.visible && Power.on_ac
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 1000
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) Quickshell.execDetached(["systemctl", "--user", "restart", "voxtype"]);
            else Quickshell.execDetached(["sh", "-c", "exec ~/.config/hypr/scripts/voxtype-with-media-pause.sh"]);
        }
    }
}
