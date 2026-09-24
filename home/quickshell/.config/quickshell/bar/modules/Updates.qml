// home/quickshell/.config/quickshell/bar/modules/Updates.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

Item {
    id: root

    property bool compact: false
    property string screen_name: ""
    property Item island: null
    property color island_color: Theme.bg_core

    readonly property int official_count: UpdatesState.official.length
    readonly property int aur_count: UpdatesState.aur.length

    readonly property bool shown: UpdatesState.total > 0 || UpdatesState.error !== ""
    visible: shown
    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    readonly property string tooltip_text: {
        const lines = ["Official: " + root.official_count, "AUR: " + root.aur_count];
        if (UpdatesState.checking) lines.push("Checking…");
        else if (UpdatesState.error) lines.push(UpdatesState.error);
        return lines.join("\n");
    }

    onIslandChanged: if (root.island) Popups.register_default("updates", root.island, root.island_color, root.screen_name, root)
    Component.onDestruction: Popups.unregister("updates", root.screen_name, root)

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Style.bar_radius(4)
        color: Style.bar_hover_bg
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    // A glyph with its count as a small badge at the top right, like the keeptabs module.
    component BadgedGlyph: Item {
        id: badged
        property string glyph: ""
        property string count: ""
        property color tint: Theme.yellow

        implicitWidth: glyph_text.implicitWidth + count_text.implicitWidth * 0.6
        implicitHeight: glyph_text.implicitHeight

        Text {
            id: glyph_text
            text: badged.glyph
            color: badged.tint
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Theme.glyph_size
        }

        Text {
            id: count_text
            x: glyph_text.implicitWidth - implicitWidth * 0.4
            y: -3
            text: badged.count
            color: badged.tint
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_font_size - 3
            font.bold: true
        }
    }

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        BadgedGlyph {
            Layout.alignment: Qt.AlignVCenter
            visible: root.official_count > 0
            glyph: "󰮯"
            count: String(root.official_count)
        }

        BadgedGlyph {
            Layout.alignment: Qt.AlignVCenter
            visible: root.aur_count > 0
            glyph: "󰏗"
            count: String(root.aur_count)
        }

        // A failed check with no counts would otherwise leave an empty, clickable gap.
        BadgedGlyph {
            Layout.alignment: Qt.AlignVCenter
            visible: root.official_count === 0 && root.aur_count === 0 && UpdatesState.error !== ""
            glyph: "󰮯"
            count: "!"
            tint: Theme.warning
        }
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, root.tooltip_text);
            else Tooltip.hide();
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                UpdatesState.refresh();
            } else {
                Popups.toggle("updates", root.island, root.island_color, root.screen_name);
            }
        }
    }
}
