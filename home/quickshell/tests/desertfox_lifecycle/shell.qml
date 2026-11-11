import QtQuick
import Quickshell
import qs.features.desertfox

// Harness shell for run.py: loads the real DesertfoxState (stubs stand in for Theme, WindowState and VoxSessionState) and
// prints one `STATE` line to stdout whenever any of what the bar reads from it changes, for run.py to wait on.
ShellRoot {
    id: root

    readonly property string line: "STATE live=" + (DesertfoxState.live ? 1 : 0) + " shown=" + (DesertfoxState.shown ? 1 : 0)
        + " chip=" + DesertfoxState.chip_label
    onLineChanged: console.log(root.line)
}
