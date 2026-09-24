// home/quickshell/.config/quickshell/components/KeyBadge.qml
import QtQuick
import "../theme"

Rectangle {
    id: root

    readonly property var st: Style.for_item(root)

    property string key: ""
    // Set on a filled active tab so an outline badge takes the tab's text color; keycap badges keep theirs.
    property bool on_fill: false
    readonly property bool tinted: root.on_fill && root.st.key_bg.a === 0

    implicitWidth: Math.max(implicitHeight, key_text.implicitWidth + 8) + root.st.slant * implicitHeight
    implicitHeight: key_text.implicitHeight + 2
    width: implicitWidth
    height: implicitHeight
    radius: Style.radius(3)
    color: root.st.slant > 0 ? "transparent" : root.st.key_bg
    border.width: root.st.slant > 0 ? 0 : 1
    border.color: root.tinted ? root.st.tab_active_fg : root.st.key_border

    Slant {
        visible: root.st.slant > 0
        color: root.st.key_bg
        border.width: 1
        border.color: root.border.color
    }

    Text {
        id: key_text
        anchors.centerIn: parent
        text: root.key
        color: root.tinted ? root.st.tab_active_fg : root.st.key_fg
        font.family: root.st.font_family
        font.pixelSize: root.st.font_size - 5
        font.bold: true
    }
}
