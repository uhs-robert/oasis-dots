import QtQuick
import Quickshell
import qs.core
import qs.theme
import qs.styles.goldeneye as Watch

// A live watch dial for the Settings panel: DialFace with the pale hands, laid out as in ClockFace but without its digits.
Item {
    id: root

    // The host says whether Settings is open; the watch adds its own visibility, so a hidden dial does not wake.
    property bool running: false
    readonly property bool awake: root.running && root.visible
    // Seconds hand only on AC; on battery the face shows the minute (as ClockFace does).
    readonly property bool live: root.awake && PowerSource.on_ac
    readonly property date now: clock.date
    readonly property real k: face.panel_item.height / 485

    implicitWidth: face.width
    implicitHeight: face.height

    SystemClock {
        id: clock
        enabled: root.awake
        precision: root.live ? SystemClock.Seconds : SystemClock.Minutes
    }

    DialFace {
        id: face
        width: root.width
        height: root.height

        Watch.WatchHands {
            x: face.panel_item.width / 2 - 510 * root.k
            y: face.panel_item.height / 2 - 360 * root.k
            scale: root.k
            transformOrigin: Item.TopLeft
            now: root.now
            show_seconds: root.live
        }
    }
}
