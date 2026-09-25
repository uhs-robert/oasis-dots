// home/quickshell/.config/quickshell/components/Callout.qml
import QtQuick
import QtQuick.Layouts
import "../theme"

// A leader line out to a small caps label over its value.
RowLayout {
    id: root

    property var st: Style.for_item(root)
    property string label: ""
    property string value: ""
    property color value_color: root.st.text_strong
    // The long form: a smaller value that may wrap onto a second line.
    property bool small: false

    spacing: 8

    Rectangle {
        Layout.preferredWidth: 26
        Layout.preferredHeight: 1
        Layout.alignment: Qt.AlignVCenter
        color: root.st.hairline
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 1

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: root.label
            color: root.st.text_muted
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-5)
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 2.5
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: root.value
            wrapMode: root.small ? Text.Wrap : Text.NoWrap
            maximumLineCount: root.small ? 2 : 1
            elide: Text.ElideRight
            color: root.small ? root.st.text_fg : root.value_color
            font.family: root.st.font_family
            font.pixelSize: root.small ? root.st.fs(-3) : root.st.fs(-1)
            font.letterSpacing: 0.5
        }
    }
}
