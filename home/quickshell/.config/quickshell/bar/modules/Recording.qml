// home/quickshell/.config/quickshell/bar/modules/Recording.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

BarModule {
    id: root
    module_name: "recording"
    has_popup: false

    // A pending capture countdown takes the chip before the recording it may start.
    readonly property bool counting: Screenshot.countdown > 0
    readonly property bool scrolling: Screenshot.scrolling
    shown: Screenshot.recording || root.counting || root.scrolling
    tooltip_text: root.scrolling ? "Scroll capture, " + Screenshot.scroll_frames + " frames\nClick or Print to stop" : root.counting ? "Capture in " + Screenshot.countdown + "s\nClick to cancel" : "Recording " + Screenshot.elapsed_text + "\nClick to stop"
    onTooltip_textChanged: if (root.hovered) Tooltip.show(root, root.tooltip_text, "recording")
    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Text {
            id: dot
            Layout.alignment: Qt.AlignVCenter
            text: root.scrolling ? "\u{f0a6d}" : root.counting ? "\u{f051b}" : "\u{f044a}"
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
            visible: !root.compact || root.counting || root.scrolling
            Layout.alignment: Qt.AlignVCenter
            text: root.scrolling ? String(Screenshot.scroll_frames) : root.counting ? String(Screenshot.countdown) : Screenshot.elapsed_text
            color: Style.bar_fg
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_font_size
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.scrolling ? Screenshot.stop_scroll() : Screenshot.stop_recording()
    }
}
