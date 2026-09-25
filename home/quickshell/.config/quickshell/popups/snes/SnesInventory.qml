// home/quickshell/.config/quickshell/popups/snes/SnesInventory.qml
import QtQuick
import "../../components"
import "../../components/snes" as Snes
import "../../theme"

// Updates as the FF6 inventory: a description window for the selected package over a two-column item list.
Item {
    id: root

    property var items: []
    property int selected: 0
    property bool aur: false
    signal clicked(int index)

    readonly property int columns: root.width >= 340 ? 2 : 1
    readonly property var current: root.items[root.selected] || null

    function glyph(name) {
        if (name.startsWith("python")) return ["", Theme.yellow];
        if (name.startsWith("linux") || name.indexOf("firmware") >= 0) return ["", Theme.fg_strong];
        if (name.startsWith("lib")) return ["", Theme.cyan];
        if (/^(ttf|otf|noto)-/.test(name)) return ["", Theme.magenta];
        if (name.startsWith("rust") || name.startsWith("cargo")) return ["", Theme.bright_yellow];
        if (name.startsWith("node") || name.startsWith("npm")) return ["", Theme.green];
        return root.aur ? ["", Theme.blue] : ["", Theme.theme_primary_light];
    }

    // The count column: the new version without epoch or pkgrel.
    function short_version(v) {
        return String(v || "").replace(/^\d+:/, "").replace(/-[^-]*$/, "");
    }

    Snes.SnesWindow {
        id: desc_window
        width: root.width
        height: desc_text.implicitHeight + 20 + desc_window.drop
    }

    Text {
        id: desc_text
        x: 12
        y: 10
        width: root.width - 24 - desc_window.drop
        elide: Text.ElideLeft
        textFormat: Text.StyledText
        text: root.current ? root.current.name + "  " + root.current.old + " → <font color=\"" + Theme.theme_secondary + "\">" + root.current.new + "</font>" : ""
        color: Theme.fg_strong
        style: Text.Raised
        styleColor: Style.text_shadow
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
    }

    Snes.SnesWindow {
        id: list_window
        y: desc_window.height + 2
        width: root.width
        height: root.height - y
    }

    GridView {
        id: grid
        x: 6
        y: list_window.y + 8
        width: root.width - 12 - list_window.drop
        height: list_window.height - 16 - list_window.drop
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cellWidth: Math.floor(grid.width / root.columns)
        cellHeight: Style.px(24)
        model: root.items
        currentIndex: root.selected
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: grid.positionViewAtIndex(grid.currentIndex, GridView.Contain)

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool selected: cell.index === root.selected
            readonly property var icon: root.glyph(cell.modelData.name)

            width: grid.cellWidth
            height: grid.cellHeight

            HandCursor {
                visible: cell.selected
                x: 1
                anchors.verticalCenter: parent.verticalCenter
                width: 17
                height: 11
            }

            Text {
                id: icon_text
                x: 21
                width: 16
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: cell.icon[0]
                color: cell.icon[1]
                font.family: Theme.font_family
                font.pixelSize: Style.fs(-3)
            }

            RowLabel {
                x: icon_text.x + icon_text.width + 5
                width: Math.max(0, count_text.x - x - 6)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                label: cell.modelData.name
                color: Theme.fg_strong
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
            }

            Text {
                id: count_text
                x: cell.width - width - 8
                width: Math.min(implicitWidth, cell.width * 0.4)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
                text: ":" + root.short_version(cell.modelData.new)
                color: Theme.fg_strong
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.clicked(cell.index)
            }
        }
    }
}
