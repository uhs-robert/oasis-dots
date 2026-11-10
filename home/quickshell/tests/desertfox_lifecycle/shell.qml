import QtQuick
import Quickshell
import qs.features.popups
import qs.features.desertfox

// Harness shell for run.py: loads the real DesertfoxState and DesertfoxWhichKey (stubs stand in for Theme, WindowState,
// VoxSessionState and the WhichKey window) and prints one `STATE` line to stdout whenever any of what the bar and the
// panel read from them changes, for run.py to wait on.
ShellRoot {
    id: root

    readonly property string line: "STATE live=" + (DesertfoxState.live ? 1 : 0) + " shown=" + (DesertfoxState.shown ? 1 : 0)
        + " chip=" + DesertfoxState.chip_label + " panel=" + (DesertfoxState.has_panel ? 1 : 0)
        + " shows=" + FakeWhichKey.shows + " hides=" + FakeWhichKey.hides
    onLineChanged: console.log(root.line)

    DesertfoxWhichKey {}
}
