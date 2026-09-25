// home/quickshell/.config/quickshell/components/TitleStrip.qml
import QtQuick
import "../theme"
import "../services"

// A VGUI window title strip: tracked caps on a tinted band over a hairline, with a close box at the right.
Item {
    id: root

    property var st: Style.for_item(root)
    property string title: ""
    property string readout_value: ""
    property bool closable: true
    // Overrides the title colour when set, e.g. with the active submap's.
    property color title_color: "transparent"

    implicitHeight: Math.max(24, title_text.implicitHeight + 10)
    // The narrowest width that shows the whole title; mirrors title_text's width limit.
    readonly property real min_width: title_text.x + title_text.implicitWidth + 8 + 22 + (value_text.visible ? value_text.implicitWidth + 8 : 0)

    Rectangle {
        anchors.fill: parent
        color: root.st.title_strip
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: root.st.hairline.a > 0 ? root.st.hairline : root.st.frame_border_color
    }

    Text {
        id: title_text
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(implicitWidth, (value_text.visible ? value_text.x : close_box.x) - x - 8))
        elide: Text.ElideRight
        text: root.title
        color: root.title_color.a > 0 ? root.title_color : root.st.title_fg
        font.family: root.st.title_font_family
        font.pixelSize: root.st.fs(-3)
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: root.st.title_spacing
    }

    Text {
        id: value_text
        visible: root.readout_value !== ""
        anchors.right: close_box.visible ? close_box.left : parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.readout_value
        color: root.st.text_muted
        font.family: root.st.number_font
        font.pixelSize: root.st.fs(-4)
        font.bold: true
    }

    Rectangle {
        id: close_box
        visible: root.closable
        anchors.right: parent.right
        anchors.rightMargin: 7
        anchors.verticalCenter: parent.verticalCenter
        width: 15
        height: 15
        color: close_area.containsMouse ? root.st.title_strip : "transparent"
        border.width: 1
        border.color: root.st.hairline_dim.a > 0 ? root.st.hairline_dim : root.st.frame_border_color

        Text {
            anchors.centerIn: parent
            text: "×"
            color: root.st.text_muted
            font.family: root.st.number_font
            font.pixelSize: 11
            font.bold: true
        }

        MouseArea {
            id: close_area
            anchors.fill: parent
            anchors.margins: -3
            hoverEnabled: true
            onClicked: Popups.close()
        }
    }
}
