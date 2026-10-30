pragma Singleton
import QtQuick
import Quickshell

// Tells every WindowSegment (one per screen) to look again. A tmux hook burst arrives as several calls, so they
// collapse into one signal after a short quiet spell, which keeps it to one window-cwd run per segment.
Singleton {
    id: root

    signal requested

    function request() {
        settle.restart();
    }

    Timer {
        id: settle
        interval: 75
        onTriggered: root.requested()
    }
}
