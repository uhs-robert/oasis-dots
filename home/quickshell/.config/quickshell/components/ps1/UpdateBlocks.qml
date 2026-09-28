// home/quickshell/.config/quickshell/components/ps1/UpdateBlocks.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"

// Updates as a memory card: a row per package under the selected save's info panel; only the selected row shows its block.
ColumnLayout {
    id: root

    property var packages: []
    property int selected: 0
    signal picked(int index)

    readonly property var current: root.packages[root.selected] || null

    function reveal(index) {
        list.positionViewAtIndex(index, ListView.Contain);
    }

    spacing: 6

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: info.implicitHeight + 12
        radius: 6
        color: Qt.alpha(Theme.bg_shadow, 0.35)
        border.width: 2
        border.color: Style.frame_border_color

        RowLayout {
            id: info
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 8
            spacing: 10

            MemBlock {
                size: Style.px(34)
                lit: true

                PackageIcon {
                    anchors.centerIn: parent
                    size: parent.width - 10
                    name: root.current ? root.current.name : ""
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.current ? root.current.name : ""
                    color: Style.text_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-2)
                    style: Text.Raised
                    styleColor: Style.text_shadow
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideLeft
                    textFormat: Text.StyledText
                    text: root.current ? root.current.old + " → <font color=\"" + Theme.yellow + "\">" + root.current.new + "</font>" : ""
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                }
            }

            Text {
                text: String(root.selected + 1).padStart(2, "0") + "/" + String(root.packages.length).padStart(2, "0")
                color: Theme.theme_primary_light
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-4)
            }
        }
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 3
        model: root.packages
        currentIndex: root.selected
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool lit: row.index === root.selected

            width: list.width
            height: Style.px(30)

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: row.lit ? Style.selection_bg : Qt.alpha(Theme.bg_shadow, 0.3)
                border.width: 2
                border.color: row.lit ? Theme.theme_primary_light : Qt.alpha(Style.frame_border_color, 0.6)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                Text {
                    text: String(row.index + 1).padStart(2, "0")
                    color: row.lit ? Theme.theme_primary_light : Style.text_dim
                    font.family: Style.mono_font
                    font.pixelSize: Style.fs(-6)
                }

                Item {
                    Layout.preferredWidth: Style.px(22)
                    Layout.preferredHeight: Style.px(22)

                    MemBlock {
                        anchors.fill: parent
                        visible: row.lit
                        size: parent.width
                        lit: true

                        PackageIcon {
                            anchors.centerIn: parent
                            size: parent.width - 6
                            name: row.modelData.name
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: row.modelData.name
                    color: row.lit ? Style.text_strong : Style.text_fg
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                }

                Text {
                    Layout.maximumWidth: list.width * 0.4
                    elide: Text.ElideLeft
                    text: row.modelData.new
                    color: row.lit ? Theme.yellow : Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.picked(row.index)
            }
        }
    }
}
