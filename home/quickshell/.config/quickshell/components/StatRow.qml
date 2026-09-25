// home/quickshell/.config/quickshell/components/StatRow.qml
import QtQuick
import QtQuick.Layouts
import "../theme"

// A spec-sheet line: tracked caps label, value and unit at the right, a thin segmented bar under both.
ColumnLayout {
    id: root

    property var st: Style.for_item(root)
    property string label: ""
    property string value: ""
    property string unit: ""
    property real fraction: 0

    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: root.label
            color: root.st.text_muted
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-4)
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: root.st.label_spacing * 0.7
        }

        Text {
            text: root.value
            color: root.st.text_strong
            font.family: root.st.mono_font
            font.pixelSize: root.st.fs(-3)
        }

        Text {
            visible: root.unit !== ""
            text: root.unit
            color: root.st.text_muted
            font.family: root.st.mono_font
            font.pixelSize: root.st.fs(-6)
        }
    }

    SegBar {
        Layout.fillWidth: true
        Layout.preferredHeight: 3
        last_lit: Math.round(Math.max(0, Math.min(1, root.fraction)) * 10) - 1
        on_color: root.st.meter_on
        off_color: root.st.meter_off
    }
}
