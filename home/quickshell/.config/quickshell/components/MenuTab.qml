// home/quickshell/.config/quickshell/components/MenuTab.qml
import QtQuick
import QtQuick.Layouts
import "../theme"

// A tab or sub-view chip; tabs fill their row, chips size to the label.
Rectangle {
    id: root

    readonly property var st: Style.for_item(root)

    property string label: ""
    property bool active: false
    property int font_size: root.st.font_size - 2
    property real base_radius: 4
    // The tab's 1-9 jump key, drawn as a badge by styles that show keys.
    property string key: ""

    readonly property bool is_chip: !root.Layout.fillWidth
    readonly property bool show_key: root.st.tab_keys && !root.is_chip && root.key !== ""
    readonly property real key_space: root.show_key ? key_badge.width + 6 : 0

    signal clicked()

    // Filling tabs share their row evenly, so they must not ask for the label's width.
    implicitWidth: root.is_chip ? label_text.implicitWidth + 20 : 0
    implicitHeight: Style.px(24)
    radius: Style.radius(root.base_radius)
    readonly property color fill: !root.active ? "transparent" : root.is_chip ? root.st.chip_active_bg : root.st.tab_active_bg
    color: root.st.slant > 0 ? "transparent" : root.fill

    Slant {
        visible: root.st.slant > 0 && root.active
        color: root.fill
    }

    KeyBadge {
        id: key_badge
        visible: root.show_key
        anchors.right: label_text.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        key: root.key
        on_fill: root.active
    }

    Text {
        id: label_text
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.key_space / 2
        width: Math.min(implicitWidth, parent.width - 8 - root.key_space)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.st.chip_brackets && root.is_chip ? (root.active ? "[" + root.label + "]" : " " + root.label + " ") : root.label
        color: !root.active ? root.st.tab_fg : root.is_chip ? root.st.chip_active_fg : root.st.tab_active_fg
        font.bold: root.active
        font.family: root.st.font_family
        font.pixelSize: root.font_size
        font.capitalization: root.st.tab_caps ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: root.st.tab_caps ? root.st.label_spacing : 0
    }

    Rectangle {
        visible: root.active && !root.is_chip && root.st.tab_underline.a > 0
        anchors.bottom: parent.bottom
        width: parent.width
        height: 2
        color: root.st.tab_underline
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
