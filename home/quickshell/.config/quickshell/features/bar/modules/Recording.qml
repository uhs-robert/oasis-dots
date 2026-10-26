import QtQuick
import QtQuick.Layouts
import qs.core
import qs.theme
import qs.features.bar
import qs.features.screenshot
import qs.features.popups

BarModule {
    id: root
    module_name: "recording"
    has_popup: false

    // A pending capture countdown takes the chip before the recording it may start.
    readonly property bool counting: Screenshot.countdown > 0
    readonly property bool scrolling: Screenshot.scrolling
    readonly property string label: root.scrolling ? String(Screenshot.scroll_frames) : root.counting ? String(Screenshot.countdown) : Screenshot.elapsed_text
    shown: Screenshot.recording || root.counting || root.scrolling
    tooltip_text: root.scrolling ? "Scroll capture, " + Screenshot.scroll_frames + " frames\nClick or Print to stop" : root.counting ? "Capture in " + Screenshot.countdown + "s\nClick to cancel" : "Recording " + Screenshot.elapsed_text + "\nClick to stop"
    onTooltip_textChanged: if (root.hovered) Tooltip.show(root, root.tooltip_text, "recording")
    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    Component.onCompleted: Screenshot.recording_chips++
    Component.onDestruction: Screenshot.recording_chips--

    ModuleRow {
        id: row
        vertical: root.vertical
        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        spacing: root.vertical ? 2 : 6

        BarIcon {
            id: dot
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            ink_centre: root.vertical
            name: "recording"
            variant: root.scrolling ? "scrolling" : root.counting ? "counting" : "default"
            glyph: root.scrolling ? "\u{f0a6d}" : root.counting ? "\u{f051b}" : "\u{f044a}"
            tint: root.counting ? Theme.warning : Theme.theme_label

            SequentialAnimation {
                running: root.shown && PowerSource.on_ac
                loops: Animation.Infinite
                onRunningChanged: if (!running) dot.opacity = 1

                NumberAnimation { target: dot; property: "opacity"; from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutQuad }
                NumberAnimation { target: dot; property: "opacity"; from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutQuad }
            }
        }

        // Kept as the plain Text on a top bar: VerticalText adds the style's letter spacing and capitalization, which this label never had.
        Text {
            visible: !root.vertical && (!root.compact || root.counting || root.scrolling)
            Layout.alignment: Qt.AlignVCenter
            text: root.label
            color: Style.bar_fg
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_font_size
        }

        VerticalText {
            visible: root.vertical && (!root.compact || root.counting || root.scrolling)
            Layout.alignment: Qt.AlignHCenter
            vertical: true
            cross: root.cross
            // Minutes over seconds: "00:00" in one line is too wide for a narrow bar even at the smallest size.
            full_text: root.label.split(":").join("\n")
            full_template: "00"
            color: Style.bar_fg
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.scrolling ? Screenshot.stop_scroll() : Screenshot.stop_recording()
    }
}
