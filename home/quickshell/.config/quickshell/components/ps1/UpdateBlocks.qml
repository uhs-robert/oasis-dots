// home/quickshell/.config/quickshell/components/ps1/UpdateBlocks.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"

// Updates as a memory card: a block per package (icon, name, slot count) under the selected save's info panel.
ColumnLayout {
    id: root

    property var packages: []
    property int selected: 0
    signal picked(int index)

    readonly property var current: root.packages[root.selected] || null
    readonly property real tile_min: Style.px(92)
    readonly property int columns: Math.max(2, Math.floor(grid.width / root.tile_min))

    function reveal(index) {
        grid.positionViewAtIndex(index, GridView.Contain);
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
                    font.pixelSize: Style.font_size - 2
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
                    font.pixelSize: Style.font_size - 4
                }
            }

            Text {
                text: String(root.selected + 1).padStart(2, "0") + "/" + String(root.packages.length).padStart(2, "0")
                color: Theme.theme_primary_light
                font.family: Style.mono_font
                font.pixelSize: Style.font_size - 4
            }
        }
    }

    GridView {
        id: grid
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: root.packages
        currentIndex: root.selected
        cellWidth: Math.floor(width / root.columns)
        cellHeight: Style.px(62)
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: tile
            required property var modelData
            required property int index
            readonly property bool lit: tile.index === root.selected

            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: 4
                color: tile.lit ? Style.selection_bg : Qt.alpha(Theme.bg_shadow, 0.3)
                border.width: 2
                border.color: tile.lit ? Theme.theme_primary_light : Qt.alpha(Style.frame_border_color, 0.6)

                Text {
                    x: 5
                    y: 3
                    text: String(tile.index + 1).padStart(2, "0")
                    color: tile.lit ? Theme.theme_primary_light : Style.text_dim
                    font.family: Style.mono_font
                    font.pixelSize: Style.font_size - 7
                }

                PackageIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 6
                    size: Style.px(22)
                    name: tile.modelData.name
                }

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: tile.modelData.name
                    color: tile.lit ? Style.text_strong : Style.text_fg
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size - 6
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.picked(tile.index)
            }
        }
    }
}
