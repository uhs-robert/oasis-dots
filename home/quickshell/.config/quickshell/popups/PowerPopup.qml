// home/quickshell/.config/quickshell/popups/PowerPopup.qml
import QtQuick
import "../components"
import "../services"

Popup {
    id: root

    popup_name: "power"
    preferred_width: 180
    footer_hint: "y/Enter confirm · n/Esc cancel"
    body_height: content.implicitHeight + 24

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: confirm_row.implicitHeight
        focus: true

        Keys.onPressed: event => confirm_row.handle_key(event)

        PowerConfirm {
            id: confirm_row
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            st: root.st
            action: Popups.power_action
            onConfirmed: {
                Power.run(confirm_row.action);
                Popups.close();
            }
            onCancelled: Popups.close()
        }
    }
}
