import QtQuick
import qs.theme
import qs.ui.keys
import "HintData.js" as HintData

// The hint bar's contents: a mode block on the left (mode, the bar's edge in VISUAL, the layout's sharing), then one column
// per key group with a small heading over its keys. The keys come from HintData.
Row {
    id: root
    property bool carrying: false
    property bool vertical: false
    readonly property var groups: HintData.groups(BarEditor.mode, root.carrying, root.vertical, BarEditor.can_forget, BarEditor.mode === "visual" ? (BarEditor.bar_compact ? "on" : "off") : BarEditor.selected_compact)
    // Monitor select already titles its box.
    readonly property string mode_label: BarEditor.mode === "monitor" ? "" : BarEditor.mode_label
    readonly property string edge_label: BarEditor.mode === "visual" ? BarEditor.position_edge + " edge" : ""
    readonly property string state_label: BarEditor.sharing ? "shared x" + BarEditor.sharing_count : "own layout"
    spacing: 18

    HintModeBlock {
        visible: root.mode_label !== ""
        anchors.verticalCenter: parent.verticalCenter
        title: root.mode_label
        Text {
            visible: root.edge_label !== ""
            text: root.edge_label
            color: Style.title_fg
            font.family: Style.font_family
            font.pixelSize: Style.fs(-2)
        }
        Text {
            text: root.state_label
            color: Style.title_fg
            opacity: 0.7
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }
        Text {
            visible: BarEditor.notice !== ""
            text: BarEditor.notice
            color: Style.accent_color
            font.family: Style.font_family
            font.pixelSize: Style.fs(-2)
        }
    }
    HintGroups {
        anchors.verticalCenter: parent.verticalCenter
        groups: root.groups
    }
}
