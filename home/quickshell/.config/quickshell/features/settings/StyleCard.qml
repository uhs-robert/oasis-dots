import QtQuick
import QtQuick.Layouts
import qs.theme

// One style in the Style gallery: a static thumb drawn from the style's own tokens (no screenshots), plus its label.
Rectangle {
    id: root

    required property string style_name
    // The saved style, marked with a tick.
    property bool current: false
    // The gallery cursor is on this card.
    property bool picked: false
    // A larger card draws more of the thumb and a bigger label.
    property bool large: false
    property var st: Style
    signal clicked

    readonly property var t: Style.styles[root.style_name] || ({})
    readonly property color bg: root.t.frame_color || Style.frame_color
    readonly property color fg: root.t.text_fg || Style.text_fg
    readonly property color accent: root.t.accent_color || Style.accent_color
    readonly property color edge: root.t.frame_border_color || root.fg
    readonly property string face: root.t.font_family || Style.font_family
    readonly property real unit: root.large ? 1.6 : 1

    Layout.fillWidth: true
    Layout.preferredHeight: Math.round(root.width * 0.78)
    color: root.picked ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22) : "transparent"
    radius: Style.px(6)
    border.width: root.picked ? 2 : 1
    border.color: root.picked ? root.accent : Style.frame_border_color

    Rectangle {
        id: thumb
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 4
        height: Math.round(parent.height * 0.62)
        color: root.bg
        radius: Math.min(Style.px(4), (root.t.frame_radius || 4) / 3)
        border.width: 1
        border.color: root.edge
        clip: true

        // A mock bar along the top.
        Rectangle {
            x: 4
            y: 4
            width: parent.width - 8
            height: Math.max(5, Math.round(parent.height * 0.18))
            radius: 2
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)

            Rectangle {
                x: 3
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(parent.width * 0.16)
                height: Math.max(3, parent.height - 4)
                radius: 1
                color: root.accent
            }
        }

        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Math.round(parent.height * 0.12)
            text: "Aa 09"
            color: root.fg
            font.family: root.face
            font.pixelSize: Math.round(thumb.height * 0.34)
        }
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: thumb.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        spacing: 4

        Text {
            Layout.fillWidth: true
            text: Style.label(root.style_name)
            elide: Text.ElideRight
            color: root.picked ? Style.text_strong : Style.text_fg
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(root.large ? 2 : -2)
            font.bold: root.picked
        }

        Text {
            visible: root.current
            text: "✓"
            color: root.accent
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(root.large ? 2 : -2)
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
