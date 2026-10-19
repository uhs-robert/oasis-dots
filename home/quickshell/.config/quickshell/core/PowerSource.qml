pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Mains power as a gate: true on AC, so animations and polling may run.
Singleton {
    readonly property bool on_ac: !UPower.onBattery
}
