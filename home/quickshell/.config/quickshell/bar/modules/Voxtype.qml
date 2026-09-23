// home/quickshell/.config/quickshell/bar/modules/Voxtype.qml
import QtQuick
import Quickshell
import "../../theme"
import "../../services"

Item {
    id: root

    property bool compact: false

    readonly property var glyphs: ({ idle: "", recording: "", transcribing: "", stopped: "" })
    readonly property color glyph_color: VoxtypeState.recording ? Theme.theme_label : VoxtypeState.transcribing ? Theme.warning : VoxtypeState.state === "stopped" ? Theme.fg_dim : Theme.theme_primary

    implicitWidth: glyph.implicitWidth
    implicitHeight: glyph.implicitHeight

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: 4
        color: Theme.bg_surface
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    Text {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        text: root.glyphs[VoxtypeState.state] || root.glyphs.idle
        color: root.glyph_color
        font.family: Theme.font_family
        font.pixelSize: Theme.glyph_size
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, VoxtypeState.tooltip);
            else Tooltip.hide();
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
