import QtQuick
import qs.theme
import "HintData.js" as HintData

// The hint bar's contents for the current mode; BarEditor.hint_design picks one of the look prototypes.
Item {
    id: root
    property bool carrying: false
    property bool vertical: false
    readonly property var groups: HintData.groups(BarEditor.mode, root.carrying, root.vertical, BarEditor.can_forget)
    // Monitor select already titles its box.
    readonly property string mode_label: BarEditor.mode === "monitor" ? "" : BarEditor.mode_label
    readonly property string state_label: BarEditor.mode === "monitor" ? "" : (BarEditor.sharing ? "shared x" + BarEditor.sharing_count : "own layout")
    implicitWidth: loader.item ? loader.item.implicitWidth : 0
    implicitHeight: loader.item ? loader.item.implicitHeight : 0
    Loader {
        id: loader
        anchors.centerIn: parent
        sourceComponent: BarEditor.hint_design === "caps" ? caps : BarEditor.hint_design === "dense" ? dense : split
    }
    Component { id: caps; HintCaps { groups: root.groups; mode_label: root.mode_label === "" ? "" : "-- " + root.mode_label + " --" } }
    Component { id: dense; HintDense { groups: root.groups; mode_label: root.mode_label } }
    Component { id: split; HintSplit { groups: root.groups; mode_label: root.mode_label; state_label: root.state_label } }
}
