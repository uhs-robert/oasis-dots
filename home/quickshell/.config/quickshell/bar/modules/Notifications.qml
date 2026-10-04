// home/quickshell/.config/quickshell/bar/modules/Notifications.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components"

BarModule {
    id: root
    module_name: "notifications"

    // Set by a lualine section with a strong fill.
    property bool on_accent: false
    // A lualine accent section draws the wash itself.
    wash: !root.on_accent

    readonly property int unread: NotificationState.unread
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    tooltip_text: {
        const count = NotificationState.history.length + " notification" + (NotificationState.history.length === 1 ? "" : "s");
        return NotificationState.dnd ? count + "\nDo not disturb" : count;
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

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                NotificationState.toggle_dnd();
            } else {
                root.toggle_popup();
            }
        }
    }
}
