import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.theme
import qs.components.bar_icons
import qs.features.power
import qs.features.voice

BarModule {
    id: root
    module_name: "voxtype"
    has_popup: false
    // The detector holding the microphone is told apart from a recording by a dot, not by the icon's colour or pulse.
    readonly property bool wake_listening: VoxWake.armed && VoxtypeState.state === "idle"
    // A paused listener keeps a dimmed dot, so it does not read as the setting being off.
    readonly property bool wake_paused: VoxWake.paused && VoxtypeState.state === "idle"
    readonly property bool wake_ready: VoxWake.ready && VoxtypeState.recording
    tooltip_text: VoxSession.active && VoxSession.exit_hint !== "" ? VoxSession.exit_hint : root.wake_listening ? "Listening for \"Cortana\"" : root.wake_paused ? VoxWake.paused_text : VoxtypeState.tooltip

    readonly property var glyphs: ({ idle: "", stopped: "" })
    readonly property color glyph_color: VoxtypeState.recording ? Theme.theme_label : VoxtypeState.transcribing ? Theme.warning : VoxtypeState.state === "stopped" ? Theme.fg_dim : Theme.theme_primary

    shown: VoxtypeState.installed
    implicitWidth: shown ? glyph.implicitWidth + (root.wake_listening || root.wake_paused || root.wake_ready ? wake_dot.dot + 2 : 0) : 0
    implicitHeight: glyph.implicitHeight

    BarIcon {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        name: "voxtype"
        variant: VoxtypeState.state === "stopped" ? "stopped" : VoxtypeState.recording ? "recording" : VoxtypeState.transcribing ? "transcribing" : "idle"
        fallback_variant: "idle"
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

    Rectangle {
        id: wake_dot
        readonly property real dot: Math.max(4, Math.round(Style.bar_badge_size / 2.5))
        visible: root.wake_listening || root.wake_paused || root.wake_ready
        x: glyph.x + glyph.width + 2
        y: glyph.y + Math.round((glyph.height - dot) / 2)
        width: dot
        height: dot
        radius: dot / 2
        color: root.wake_ready ? Theme.ok : Theme.theme_secondary
        opacity: root.wake_paused ? 0.5 : 0.85

        SequentialAnimation {
            running: root.wake_ready
            loops: 3
            onRunningChanged: if (!running) wake_dot.opacity = Qt.binding(() => root.wake_paused ? 0.5 : 0.85)
            NumberAnimation { target: wake_dot; property: "opacity"; from: 1; to: 0.15; duration: 180 }
            NumberAnimation { target: wake_dot; property: "opacity"; from: 0.15; to: 1; duration: 180 }
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
