import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.theme
import qs.ui.keys
import qs.features.bar
import "../../ui/keys/KeyHints.js" as KeyHints

// The compact key hints of the submap Hyprland is in (Submap.define `hint`, sent over `submap_hints set`), on the
// focused screen, placed as the bar editor's hint bar: bottom centre, or top centre while that screen's bar is on the
// bottom. Display only: Hyprland's submap keeps the keyboard and the pointer passes through.
PanelWindow {
    id: root

    readonly property var hint: SubmapState.hint
    // A second line under the submap name, for state such as a selection count; empty hides it.
    property string status_text: ""
    readonly property var bar_item: root.screen ? BarItems.item_of(root.screen.name, "bar") : null
    readonly property bool on_top: root.bar_item !== null && root.bar_item.position === "bottom"
    readonly property int edge_gap: 24

    screen: {
        const mon = Hyprland.focusedMonitor;
        return (mon && Quickshell.screens.find(s => s.name === mon.name)) || null;
    }
    // Hidden while the which-key HUD SHIFT + / opens is up, which lists every key and would sit over it.
    visible: root.hint !== null && root.screen !== null && !SubmapState.whichkey_open
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors.top: root.on_top
    anchors.bottom: !root.on_top
    margins.top: root.edge_gap
    margins.bottom: root.edge_gap
    implicitWidth: plate.width
    implicitHeight: plate.height
    WlrLayershell.namespace: "quickshell-submap-hints"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    HintPlate {
        id: plate
        width: plate.implicitWidth
        height: plate.implicitHeight
        Row {
            anchors.centerIn: parent
            spacing: 18
            HintModeBlock {
                id: mode_block
                anchors.verticalCenter: parent.verticalCenter
                title: root.hint ? root.hint.name : ""
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.status_text !== ""
                    text: root.status_text
                    color: Style.title_fg
                    opacity: 0.7
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                }
                // Esc and the ? that opens the full which-key list.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Repeater {
                        model: root.hint ? root.hint.footer || [] : []
                        Row {
                            id: footer_key
                            required property var modelData
                            spacing: 3
                            Text {
                                text: KeyHints.with_glyphs(footer_key.modelData[0])
                                color: Style.title_fg
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-3)
                                font.bold: true
                            }
                            Text {
                                text: footer_key.modelData[1]
                                color: Style.title_fg
                                opacity: 0.7
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-3)
                            }
                        }
                    }
                }
            }
            HintGroups {
                anchors.verticalCenter: parent.verticalCenter
                groups: root.hint ? root.hint.groups : []
                // Wraps whole groups before the plate outgrows the screen.
                max_width: (root.screen ? root.screen.width : 1920) - 2 * root.edge_gap - 28 - 18 - mode_block.width
            }
        }
    }
}
