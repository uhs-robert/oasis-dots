import QtQuick
import qs.theme
import qs.styles.goldeneye as Watch

// A live watch dial for the Settings panel: the dial face with the pale hands, ticking once a second while `running`.
Item {
    id: root

    property bool running: false
    property date now: new Date()
    readonly property real k: face.panel_item.height / 485

    implicitWidth: face.width
    implicitHeight: face.height

    // A Timer rather than SystemClock so nothing wakes while Settings is closed.
    Timer {
        interval: 1000
        repeat: true
        running: root.running
        triggeredOnStart: true
        onTriggered: root.now = new Date()
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
        }
    }
}
