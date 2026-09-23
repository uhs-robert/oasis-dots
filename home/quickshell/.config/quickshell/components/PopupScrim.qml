// home/quickshell/.config/quickshell/components/PopupScrim.qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../services"

// Below the bar's reserved zone, so bar clicks still switch popups.
PanelWindow {
    id: root

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusiveZone: 0
    color: "transparent"
    visible: Popups.open_name !== ""
    WlrLayershell.namespace: "quickshell-scrim"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: Popups.close()
    }
}
