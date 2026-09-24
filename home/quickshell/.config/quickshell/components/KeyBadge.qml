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

    implicitWidth: Math.max(implicitHeight, key_text.implicitWidth + 8)
    implicitHeight: key_text.implicitHeight + 2
    width: implicitWidth
    height: implicitHeight
    radius: root.st.key_round ? height / 2 : Style.radius(3)
    readonly property bool cut: root.st.key_cut > 0
    color: root.cut ? "transparent" : root.st.key_bg
    border.width: root.cut ? 0 : 1
    border.color: root.tinted ? root.st.tab_active_fg : root.st.key_border

    CutBox {
        visible: root.cut
        anchors.fill: parent
        cut_tl: root.st.key_cut
        cut_br: root.st.key_cut
        fill: root.st.key_bg
        stroke: root.tinted ? root.st.tab_active_fg : root.st.key_border
    }

    Text {
        id: key_text
        anchors.centerIn: parent
        text: root.key
        color: root.tinted ? root.st.tab_active_fg : root.st.key_fg
        font.family: root.st.mono_font
        font.pixelSize: root.st.font_size - 5
        font.bold: root.st.mono_font === root.st.font_family
    }
}
