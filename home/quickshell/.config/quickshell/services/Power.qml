// home/quickshell/.config/quickshell/services/Power.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

Singleton {
    id: root

    readonly property bool on_ac: !UPower.onBattery
}
