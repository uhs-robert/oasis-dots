import QtQuick
import qs.theme
import "../../ui/keys/KeyHints.js" as KeyHints
import "HintData.js" as HintData

// The hint bar's contents: a mode block on the left (mode, the bar's edge in VISUAL, the layout's sharing), then one column
// per key group with a small heading over its keys, so two rows never split a group. The keys come from HintData.
Row {
    id: root
    property bool carrying: false
    property bool vertical: false
    readonly property var groups: HintData.groups(BarEditor.mode, root.carrying, root.vertical, BarEditor.can_forget)
    // Monitor select already titles its box.
    readonly property string mode_label: BarEditor.mode === "monitor" ? "" : BarEditor.mode_label
    readonly property string edge_label: BarEditor.mode === "visual" ? BarEditor.position_edge + " edge" : ""
    readonly property string state_label: BarEditor.sharing ? "shared x" + BarEditor.sharing_count : "own layout"
    spacing: 18

    Rectangle {
        visible: root.mode_label !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(mode_text.implicitWidth, edge_text.implicitWidth, state_text.implicitWidth) + 24
        height: block.implicitHeight + 14
        radius: Math.min(Style.frame_radius, 4)
        color: Style.title_bg
        Column {
            id: block
            anchors.centerIn: parent
            spacing: 2
            Text {
                id: mode_text
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.mode_label
                color: Style.title_fg
                font.family: Style.title_font_family
                font.pixelSize: Style.fs(0)
                font.bold: true
            }
            Text {
                id: edge_text
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.edge_label !== ""
                text: root.edge_label
                color: Style.title_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
            }
            Text {
                id: state_text
                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.state_label
                color: Style.title_fg
                opacity: 0.7
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }
        }
    }
    Repeater {
        model: root.groups
        Column {
            id: col
            required property var modelData
            spacing: 4
            anchors.verticalCenter: parent.verticalCenter
            Text {
                text: col.modelData.name.toUpperCase()
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
                font.letterSpacing: 1.5
            }
            Rectangle {
                width: parent.width
                height: 1
                color: Style.accent_color
                opacity: 0.6
            }
            Row {
                spacing: 12
                Repeater {
                    model: col.modelData.keys
                    Row {
                        id: item
                        required property var modelData
                        spacing: 4
                        Text {
                            text: KeyHints.with_glyphs(item.modelData[0])
                            color: Style.accent_color
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-1)
                            font.bold: true
                        }
                        Text {
                            text: item.modelData[1]
                            color: Style.text_fg
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-1)
                        }
                    }
                }
            }
        }
    }
}
