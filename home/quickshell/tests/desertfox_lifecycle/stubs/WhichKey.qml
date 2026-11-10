import QtQuick
import Quickshell

// Stands in for the WhichKey window DesertfoxWhichKey drives: counts the opens and closes it is asked for.
Scope {
    id: root

    property bool wanted: false
    property bool tinted: false
    property color header_color: "transparent"

    function show_object(next): void {
        root.wanted = true;
        FakeWhichKey.shows += 1;
    }

    function hide_now(): void {
        root.wanted = false;
        FakeWhichKey.hides += 1;
    }
}
