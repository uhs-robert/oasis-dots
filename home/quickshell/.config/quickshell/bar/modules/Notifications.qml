// home/quickshell/.config/quickshell/bar/modules/Notifications.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components"

Item {
    id: root

    property bool compact: false
    property string screen_name: ""
    property Item island: null
    property color island_color: Theme.bg_core
    // Set by a lualine section with a strong fill.
    property bool on_accent: false

    readonly property int unread: NotificationState.unread
    readonly property bool shown: true
    visible: shown
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    readonly property string tooltip_text: {
        const count = NotificationState.history.length + " notification" + (NotificationState.history.length === 1 ? "" : "s");
        return NotificationState.dnd ? count + "\nDo not disturb" : count;
    }

    onIslandChanged: if (root.island) Popups.register_default("notifications", root.island, root.island_color, root.screen_name, root)
    Component.onDestruction: Popups.unregister("notifications", root.screen_name, root)

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Style.bar_radius(4)
        color: Style.bar_hover_bg
        // On a lualine accent section the section draws this wash.
        opacity: hover_handler.hovered && !root.on_accent ? 0.5 : 0
    }

    RowLayout {
        id: row
        spacing: 4

        BadgedGlyph {
            Layout.alignment: Qt.AlignVCenter
            glyph: NotificationState.dnd ? "\u{f009b}" : "\u{f009a}"
            count: root.unread > 99 ? "99+" : root.unread > 0 ? String(root.unread) : ""
            tint: root.on_accent ? Theme.bg_crust : NotificationState.dnd ? Theme.fg_dim : Theme.theme_primary
            glyph_opacity: root.on_accent && NotificationState.dnd ? 0.55 : 1
        }
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, root.tooltip_text, "notifications");
            else Tooltip.hide(root);
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                NotificationState.toggle_dnd();
            } else {
                Popups.toggle("notifications", root.island, root.island_color, root.screen_name);
            }
        }
    }
}
