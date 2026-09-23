// home/quickshell/.config/quickshell/bar/modules/Notifications.qml
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
        radius: 4
        color: Theme.bg_surface
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    RowLayout {
        id: row
        spacing: 4

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: glyph.implicitWidth
            implicitHeight: glyph.implicitHeight

            Text {
                id: glyph
                text: NotificationState.dnd ? "\u{f009b}" : "\u{f009a}"
                color: NotificationState.dnd ? Theme.fg_dim : Theme.theme_primary
                font.family: Theme.font_family
                font.pixelSize: Theme.glyph_size
            }

            Rectangle {
                visible: root.unread > 0
                width: badge_label.implicitWidth + 6
                height: 12
                radius: 6
                anchors.right: glyph.right
                anchors.top: glyph.top
                anchors.margins: -3
                color: Theme.theme_primary

                Text {
                    id: badge_label
                    anchors.centerIn: parent
                    text: root.unread > 99 ? "99+" : String(root.unread)
                    color: Theme.bg_core
                    font.family: Theme.font_family
                    font.pixelSize: Theme.font_size - 5
                    font.bold: true
                }
            }
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
                NotificationState.toggle_dnd();
            } else {
                Popups.toggle("notifications", root.island, root.island_color, root.screen_name);
            }
        }
    }
}
