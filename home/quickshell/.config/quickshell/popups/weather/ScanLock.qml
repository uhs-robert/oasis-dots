// home/quickshell/.config/quickshell/popups/weather/ScanLock.qml
import QtQuick
import "../../components"
import "../../theme"

// Scan brackets that close in on the selected day once each time it is picked.
CornerBrackets {
    id: root

    property bool shown: false

    anchors.fill: parent
    color: Theme.theme_primary
    arm: 9
    thickness: 1.5
    all_corners: true
    inset: 0

    onShownChanged: if (root.shown) lock.restart(); else lock.stop();
    Component.onCompleted: if (root.shown) lock.restart()

    ParallelAnimation {
        id: lock
        NumberAnimation { target: root; property: "inset"; from: -10; to: 0; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "opacity"; from: 0.2; to: 1; duration: 220 }
    }
}
