// home/quickshell/.config/quickshell/popups/snes/SnesStartView.qml
import QtQuick
import "../../components"
import "../../components/snes" as Snes
import "../../theme"

// Start as an FF6 main menu: the command column in a blue window, the glove on the selected command.
Item {
    id: root

    property var labels: []
    property var keys: []
    property int selected: 0
    signal picked(int index)

    implicitHeight: commands.implicitHeight + 20 + menu_window.drop

    Snes.SnesWindow {
        id: menu_window
        anchors.fill: parent
    }

    Column {
        id: commands
        x: 6
        y: 10
        width: root.width - 12 - menu_window.drop
        spacing: 2

        Repeater {
            model: root.labels

            Item {
                id: command
                required property int index
                required property string modelData
                readonly property bool selected: command.index === root.selected

                width: commands.width
                height: Style.px(24)

                HandCursor {
                    visible: command.selected
                    x: 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 19
                    height: 12
                }

                RowLabel {
                    x: 26
                    width: Math.max(0, parent.width - x - key_badge.width - 6)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    label: command.modelData
                    color: Theme.fg_strong
                    style: Text.Raised
                    styleColor: Style.text_shadow
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size
                }

                KeyBadge {
                    id: key_badge
                    visible: Style.row_keys
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    key: root.keys[command.index] || ""
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.picked(command.index)
                }
            }
        }
    }
}
