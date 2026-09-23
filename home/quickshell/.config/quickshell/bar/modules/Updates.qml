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
        radius: 4
        color: Theme.bg_surface
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    RowLayout {
        id: row
        spacing: 8

        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: root.official_count > 0
            text: "󰮯 " + root.official_count
            color: Theme.yellow
            font.family: Theme.font_family
            font.pixelSize: Theme.font_size
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: root.aur_count > 0
            text: "󰏗 " + root.aur_count
            color: Theme.yellow
            font.family: Theme.font_family
            font.pixelSize: Theme.font_size
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
