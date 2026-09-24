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
    readonly property bool bracketed: root.active && !root.is_chip && root.st.tab_brackets.a > 0
    readonly property real bracket_space: root.bracketed ? open_bracket.implicitWidth * 2 + 4 : 0

    signal clicked()

    // Filling tabs share their row evenly, so they must not ask for the label's width.
    implicitWidth: root.is_chip ? label_text.implicitWidth + 20 : 0
    implicitHeight: Style.px(24)
    radius: root.is_chip && root.st.pill_chips ? height / 2 : Style.radius(root.base_radius)
    border.width: root.is_chip && root.st.pill_chips ? 1 : 0
    border.color: root.active ? root.st.chip_active_bg : root.st.chip_border
    readonly property color fill: !root.active ? (root.is_chip ? root.st.chip_bg : root.st.tab_bg) : root.is_chip ? root.st.chip_active_bg : root.st.tab_active_bg
    readonly property real cut: root.is_chip ? root.st.key_cut : root.st.tab_cut
    color: root.cut > 0 ? "transparent" : root.fill

    CutBox {
        visible: root.cut > 0
        anchors.fill: parent
        cut_tl: root.is_chip ? root.cut : 0
        cut_tr: root.is_chip ? 0 : root.cut
        cut_br: root.is_chip ? root.cut : 0
        fill: root.fill
        fill_end: root.active && !root.is_chip ? Qt.alpha(root.fill, root.fill.a * 0.6) : root.fill
        stroke: root.is_chip && !root.active ? root.st.chip_border : "transparent"
    }

    KeyBadge {
        id: key_badge
        visible: root.show_key
        anchors.right: label_text.left
        anchors.rightMargin: 6 + root.bracket_space / 2
        anchors.verticalCenter: parent.verticalCenter
        key: root.key
        on_fill: root.active
    }

    Text {
        id: label_text
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.key_space / 2
        width: Math.min(implicitWidth, parent.width - 8 - root.key_space - root.bracket_space)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.st.chip_brackets && root.is_chip ? (root.active ? "[" + root.label + "]" : " " + root.label + " ") : root.label
        color: !root.active ? root.st.tab_fg : root.is_chip ? root.st.chip_active_fg : root.st.tab_active_fg
        font.bold: root.active
        font.family: root.st.label_font_family
        font.pixelSize: root.font_size
        font.capitalization: root.st.tab_caps ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: root.st.tab_caps ? root.st.label_spacing : 0
    }

    Text {
        id: open_bracket
        visible: root.bracketed
        anchors.right: label_text.left
        anchors.rightMargin: 2
        anchors.verticalCenter: label_text.verticalCenter
        text: "["
        color: root.st.tab_brackets
        font: label_text.font
    }

    Text {
        visible: root.bracketed
        anchors.left: label_text.right
        anchors.leftMargin: 2
        anchors.verticalCenter: label_text.verticalCenter
        text: "]"
        color: root.st.tab_brackets
        font: label_text.font
    }

    Rectangle {
        visible: !root.is_chip && root.st.tab_rule.a > 0
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: root.st.tab_rule
    }

    Rectangle {
        visible: root.active && !root.is_chip && root.st.tab_underline.a > 0
        anchors.bottom: parent.bottom
        width: parent.width
        height: root.st.hairline.a > 0 ? 1 : 2
        color: root.st.tab_underline
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
