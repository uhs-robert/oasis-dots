// home/quickshell/.config/quickshell/bar/modules/Tray.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import "../../theme"
import "../../services"

Item {
    id: root

    property bool compact: false
    property string screen_name: ""
    property Item island: null
    property color island_color: Theme.bg_core

    readonly property int count: SystemTray.items.values.length
    readonly property bool needs_attention: SystemTray.items.values.some(i => i.status === Status.NeedsAttention)
    readonly property string tooltip_text: root.count + " tray app" + (root.count === 1 ? "" : "s")

    readonly property bool shown: root.count > 0
    visible: shown
    implicitWidth: root.shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    onIslandChanged: if (root.island) Popups.register_default("tray", root.island, root.island_color, root.screen_name, root)
    Component.onDestruction: Popups.unregister("tray", root.screen_name, root)

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Style.bar_radius(4)
        color: Style.bar_hover_bg
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    RowLayout {
        id: row
        spacing: 2

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: ""
            color: Theme.theme_primary
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Theme.glyph_size
            rotation: Popups.open_name === "tray" ? -90 : 0

            Behavior on rotation {
                NumberAnimation { duration: 180; easing.type: Easing.InOutCubic }
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignTop
            visible: root.needs_attention
            implicitWidth: 5
            implicitHeight: 5
            radius: 2.5
            color: Theme.theme_accent
        }
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, root.tooltip_text, "tray");
            else Tooltip.hide(root);
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Popups.toggle("tray", root.island, root.island_color, root.screen_name)
    }
}
