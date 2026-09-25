// home/quickshell/.config/quickshell/popups/updates/NesInventory.qml
import QtQuick
import "../../components"
import "../../theme"

// A Zelda inventory: one item tile per package, the selected one boxed, its versions spelled out below.
Item {
    id: root

    required property var popup
    readonly property var st: Style.for_item(root)
    readonly property var list: root.popup.current_list
    readonly property var chosen: root.list[root.popup.selected] || null
    readonly property int columns: Math.max(1, Math.floor(root.width / Style.px(52)))

    // Sword, potion, key, rupee, bomb, shield: rows of palette indices with a palette each.
    readonly property var icons: [
        [".......2", "......20", ".....20.", "..1.20..", "...10...", "...11...", "..1..1..", ".1......"],
        ["...11...", "...22...", "..1..1..", ".100001.", ".100001.", ".100001.", "..1111..", "........"],
        [".111....", "1...1...", "1...1...", ".1111111", "....1.1.", "....1.1.", "........", "........"],
        ["...11...", "..1221..", ".120021.", ".100001.", ".100001.", ".100001.", "..1001..", "...11..."],
        [".....2..", "....1...", "..1111..", ".100001.", ".102001.", ".100001.", "..1111..", "........"],
        [".111111.", ".100001.", ".102201.", ".102201.", ".100001.", "..1001..", "...11...", "........"]
    ]
    readonly property var palettes: [
        [Theme.theme_primary_light, Theme.bright_yellow, Theme.fg_strong],
        [Theme.red, Theme.fg_dim, Theme.fg_strong],
        [Theme.yellow, Theme.yellow, Theme.yellow],
        [Theme.green, Qt.darker(Theme.green, 1.6), Theme.fg_strong],
        [Theme.blue, Theme.theme_primary_strong, Theme.bright_yellow],
        [Theme.theme_primary, Theme.bright_yellow, Theme.red]
    ]

    function icon_of(name) {
        let h = 0;
        for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) % 9973;
        return h % root.icons.length;
    }

    Connections {
        target: root.popup
        function onSelectedChanged() {
            grid.positionViewAtIndex(root.popup.selected, GridView.Contain);
        }
    }

    GridView {
        id: grid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: detail.top
        anchors.bottomMargin: 8
        clip: true
        cellWidth: Math.floor(root.width / root.columns)
        cellHeight: Style.px(52)
        model: root.list
        currentIndex: root.popup.selected
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: tile
            required property var modelData
            required property int index
            readonly property bool selected: tile.index === root.popup.selected
            readonly property int icon: root.icon_of(tile.modelData.name)

            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                visible: tile.selected
                anchors.fill: parent
                anchors.margins: 2
                color: "transparent"
                border.width: 2
                border.color: root.st.caret_color
            }

            PixelSprite {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 7
                pixel: 3
                rows: root.icons[tile.icon]
                colors: root.palettes[tile.icon].concat(["transparent"])
            }

            RowLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                width: parent.width - 8
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                label: tile.modelData.name
                color: tile.selected ? root.st.text_strong : root.st.text_muted
                font.family: root.st.font_family
                font.pixelSize: 8
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.popup.selected = tile.index
            }
        }
    }

    Column {
        id: detail
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 4

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.chosen ? root.chosen.name : ""
            color: root.st.text_strong
            font.family: root.st.font_family
            font.pixelSize: root.st.font_size - 4
        }

        Text {
            width: parent.width
            elide: Text.ElideLeft
            textFormat: Text.StyledText
            text: root.chosen ? root.chosen.old + " \u2192 <font color=\"" + Theme.yellow + "\">" + root.chosen.new + "</font>" : ""
            color: root.st.text_muted
            font.family: root.st.font_family
            font.pixelSize: root.st.font_size - 4
        }
    }
}
