// home/quickshell/.config/quickshell/popups/start/NesMenu.qml
import QtQuick
import "../../components"
import "../../components/nes" as Nes
import "../../theme"

// The NES title screen menu: numbered caps rows, a blinking cursor and a PUSH A BUTTON line.
Column {
    id: root

    required property var popup
    readonly property var st: Style.for_item(root)

    spacing: 8

    Repeater {
        model: root.popup.actions

        Item {
            id: row
            required property int index
            required property string modelData
            readonly property bool selected: row.index === root.popup.selected

            width: root.width
            height: Style.px(22)

            Text {
                visible: row.selected && Style.caret_phase
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                text: "▶"
                color: root.st.caret_color
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size
            }

            RowLabel {
                x: 6 + root.st.font_size * 2
                width: parent.width - x
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                label: (row.index + 1) + " " + row.modelData.toUpperCase()
                color: row.selected ? root.st.text_strong : root.st.text_fg
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.popup.choose(row.index)
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        topPadding: 6
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "PUSH"
            color: root.st.text_muted
            font.family: root.st.font_family
            font.pixelSize: 8
        }

        Nes.NesButton {
            anchors.verticalCenter: parent.verticalCenter
            button: "a"
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "BUTTON"
            color: root.st.text_muted
            font.family: root.st.font_family
            font.pixelSize: 8
        }
    }
}
