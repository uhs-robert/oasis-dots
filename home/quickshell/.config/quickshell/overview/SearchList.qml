// home/quickshell/.config/quickshell/overview/SearchList.qml
import QtQuick
import Quickshell.Widgets
import "../components"
import "../services"
import "../theme"

// Ranked window matches beside the overview tiles; the highlighted row is the one Enter acts on. Rows take `icon_source` or else the toplevel's icon.
Rectangle {
    id: root

    property var entries: []
    property int current: 0
    signal chosen(int index)

    color: Qt.alpha(Theme.bg_mantle, 0.85)
    radius: Style.radius(8)
    border.width: 1
    border.color: Qt.alpha(Theme.ui_border, 0.6)
    clip: true

    onCurrentChanged: list.positionViewAtIndex(root.current, ListView.Contain)

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: Style.px(6)
        model: root.entries
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        delegate: MenuRow {
            id: row
            required property var modelData
            required property int index

            width: list.width
            height: Style.px(44)
            base_radius: 6
            selected: row.index === root.current

            IconImage {
                id: row_icon
                x: 8 + row.inset
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: Style.px(24)
                asynchronous: true
                visible: source !== ""
                source: row.modelData.icon_source !== undefined ? row.modelData.icon_source : WindowState.icon_for(row.modelData.toplevel)
            }

            Text {
                id: row_title
                anchors.left: row_icon.visible ? row_icon.right : parent.left
                anchors.leftMargin: row_icon.visible ? 8 : 8 + row.inset
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.top: parent.top
                anchors.topMargin: Style.px(6)
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.modelData.title !== "" ? row.modelData.title : row.modelData.label
                color: row.fg(row.st.text_fg)
                font.family: row.st.font_family
                font.pixelSize: row.st.fs(-1)
            }

            Text {
                anchors.left: row_title.left
                anchors.right: row_title.right
                anchors.top: row_title.bottom
                anchors.topMargin: Style.px(2)
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.modelData.label + " · " + row.modelData.place
                color: row.fg(row.st.text_muted)
                font.family: row.st.font_family
                font.pixelSize: row.st.fs(-4)
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.chosen(row.index)
            }
        }
    }

    Text {
        visible: root.entries.length === 0
        anchors.centerIn: parent
        text: "No matching windows"
        color: Style.text_muted
        font.family: Style.font_family
        font.pixelSize: Style.fs(-2)
    }
}
