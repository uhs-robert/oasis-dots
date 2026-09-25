// home/quickshell/.config/quickshell/bar/modules/Voxtype.qml
import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../theme"
import "../../services"

Item {
    id: root

    property bool compact: false

    readonly property var glyphs: ({ idle: "", stopped: "" })
    readonly property color glyph_color: VoxtypeState.recording ? Theme.theme_label : VoxtypeState.transcribing ? Theme.warning : VoxtypeState.state === "stopped" ? Theme.fg_dim : Theme.theme_primary

    implicitWidth: glyph.implicitWidth
    implicitHeight: glyph.implicitHeight

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Style.bar_radius(4)
        color: Style.bar_hover_bg
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    Text {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        text: VoxtypeState.state === "stopped" ? root.glyphs.stopped : root.glyphs.idle
        color: root.glyph_color
        font.family: Style.bar_font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: Style.bar_glyph_size

        SequentialAnimation {
            id: pulse_animation
            running: VoxtypeState.recording
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
            running: ring.visible
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 1000
        }
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, VoxtypeState.tooltip, "voxtype");
            else Tooltip.hide(root);
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
