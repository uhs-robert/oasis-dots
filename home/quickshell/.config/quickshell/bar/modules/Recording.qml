// home/quickshell/.config/quickshell/bar/modules/Recording.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

Item {
    id: root

    property bool compact: false

    // A pending capture countdown takes the chip before the recording it may start.
    readonly property bool counting: Screenshot.countdown > 0
    readonly property bool shown: Screenshot.recording || root.counting
    readonly property string tip: root.counting ? "Capture in " + Screenshot.countdown + "s\nClick to cancel" : "Recording " + Screenshot.elapsed_text + "\nClick to stop"
    onTipChanged: if (hover_handler.hovered) Tooltip.show(root, root.tip, "recording")
    visible: shown
    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Style.bar_radius(4)
        color: Style.bar_hover_bg
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Text {
            id: dot
            Layout.alignment: Qt.AlignVCenter
            text: root.counting ? "\u{f051b}" : "\u{f044a}"
            color: root.counting ? Theme.warning : Theme.theme_label
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_glyph_size

            SequentialAnimation {
                running: root.shown && Power.on_ac
                loops: Animation.Infinite
                onRunningChanged: if (!running) dot.opacity = 1

                NumberAnimation { target: dot; property: "opacity"; from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutQuad }
                NumberAnimation { target: dot; property: "opacity"; from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutQuad }
            }
        }

        Text {
            visible: !root.compact || root.counting
            Layout.alignment: Qt.AlignVCenter
            text: root.counting ? String(Screenshot.countdown) : Screenshot.elapsed_text
            color: Style.bar_fg
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_font_size
        }
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, root.tip, "recording");
            else Tooltip.hide(root);
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Screenshot.stop_recording()
    }
}
