import QtQuick
import Quickshell.Hyprland
import qs.theme
import qs.ui.keys
import qs.features.bar
import "../../ui/keys/KeyHints.js" as KeyHints

// The compact key hints of the submap Hyprland is in (Submap.define `hint`, sent over `submap_hints set`), on the
// focused screen, placed as the bar editor's hint bar: bottom centre, or top centre while that screen's bar is on the
// bottom. The window is the shared HintDrawer: with the screen frame on a plain-centre drawer on that edge, like the OSD
// (grown out of the frame, folded back on close); a screen without a frame layout keeps the floating plate. Display only:
// Hyprland's submap keeps the keyboard and the pointer passes through.
HintDrawer {
    id: root

    readonly property var hint: SubmapState.hint
    // The last hint and status line shown, so the plate keeps its content and size while a drawer folds back after the submap ends.
    property var held_hint: null
    property string held_status_text: ""
    Binding {
        target: root
        property: "held_hint"
        value: root.hint
        when: root.hint !== null
        restoreMode: Binding.RestoreNone
    }
    Binding {
        target: root
        property: "held_status_text"
        value: root.status_text
        when: root.hint !== null
        restoreMode: Binding.RestoreNone
    }
    // A second line under the submap name; empty hides it.
    readonly property string status_text: WindowTargetState.active && WindowTargetState.selected.length > 0 ? WindowTargetState.selected.length + " selected" : ""
    readonly property int gap: 18
    // The room the plate's contents have on this screen: its width less the edge gaps and the plate's padding.
    readonly property real room: (root.screen ? root.screen.width : 1920) - 2 * root.edge_gap - 28
    // The name chip goes above the groups, on one line, when that saves the groups a row: on a narrow screen or with a
    // large font its column costs more than the line it takes on top.
    readonly property bool stacked: groups.fill(root.room - root.gap - mode_block.stacked_width).rows > groups.fill(root.room).rows

    // One per screen, shown on the focused one: a single window following the focus by rebinding `screen` is remapped on
    // every change, which fought the `visible` binding.
    readonly property bool focused: !!Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === root.modelData.name

    namespace: "quickshell-submap-hints"
    // Hidden while the which-key HUD SHIFT + / opens is up, which lists every key and would sit over it.
    wanted: root.hint !== null && root.focused && !SubmapState.whichkey_open
    floating_fallback: true

    Grid {
        anchors.centerIn: parent
        columns: root.stacked ? 1 : 2
        columnSpacing: root.gap
        rowSpacing: 10
        verticalItemAlignment: Grid.AlignVCenter
        HintModeBlock {
            id: mode_block
            inline: root.stacked
            title: root.held_hint ? root.held_hint.name : ""
            Text {
                visible: root.held_status_text !== ""
                text: root.held_status_text
                color: Style.title_fg
                opacity: 0.7
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }
            // Esc and the ? that opens the full which-key list.
            Row {
                spacing: 8
                Repeater {
                    model: root.held_hint ? root.held_hint.footer || [] : []
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
            id: groups
            groups: root.held_hint ? root.held_hint.groups : []
            // Wraps whole groups before the plate outgrows the screen.
            max_width: root.stacked ? root.room : root.room - root.gap - mode_block.width
        }
    }
}
