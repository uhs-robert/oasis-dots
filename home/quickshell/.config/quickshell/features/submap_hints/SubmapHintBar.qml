import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.theme
import qs.ui.keys
import qs.features.bar
import qs.ui.frames
import "../../ui/keys/KeyHints.js" as KeyHints

// The compact key hints of the submap Hyprland is in (Submap.define `hint`, sent over `submap_hints set`), on the
// focused screen, placed as the bar editor's hint bar: bottom centre, or top centre while that screen's bar is on the
// bottom. With the screen frame on it is a plain-centre drawer on that edge, like the OSD (grown out of the frame, folded
// back on close); a screen without a frame layout keeps the floating plate. Display only: Hyprland's submap keeps the
// keyboard and the pointer passes through.
PanelWindow {
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
    readonly property var bar_item: root.screen ? BarItems.item_of(root.screen.name, "bar") : null
    readonly property bool on_top: root.bar_item !== null && root.bar_item.position === "bottom"
    readonly property int edge_gap: 24
    readonly property int gap: 18
    // The room the plate's contents have on this screen: its width less the edge gaps and the plate's padding.
    readonly property real room: (root.screen ? root.screen.width : 1920) - 2 * root.edge_gap - 28
    // The name chip goes above the groups, on one line, when that saves the groups a row: on a narrow screen or with a
    // large font its column costs more than the line it takes on top.
    readonly property bool stacked: groups.fill(root.room - root.gap - mode_block.stacked_width).rows > groups.fill(root.room).rows

    // One per screen, shown on the focused one: a single window following the focus by rebinding `screen` is remapped on
    // every change, which fought the `visible` binding.
    required property var modelData
    readonly property bool focused: !!Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === root.modelData.name

    screen: root.modelData
    // Hidden while the which-key HUD SHIFT + / opens is up, which lists every key and would sit over it.
    readonly property bool wanted: root.hint !== null && root.focused && !SubmapState.whichkey_open
    // A drawer stays mapped until its fold ends.
    visible: root.wanted || (root.drawer && scaffold.progress > 0)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors.top: root.drawer ? scaffold.place.anchor_top : root.on_top
    anchors.bottom: root.drawer ? scaffold.place.anchor_bottom : !root.on_top
    anchors.left: root.drawer ? scaffold.place.anchor_left : false
    anchors.right: root.drawer ? scaffold.place.anchor_right : false
    margins.top: root.drawer ? scaffold.place.margin_top : root.edge_gap
    margins.bottom: root.drawer ? scaffold.place.margin_bottom : root.edge_gap
    margins.left: root.drawer ? scaffold.place.margin_left : 0
    margins.right: root.drawer ? scaffold.place.margin_right : 0
    implicitWidth: root.drawer ? scaffold.full.surface.width : plate.width
    implicitHeight: root.drawer ? scaffold.full.surface.height : plate.height
    WlrLayershell.namespace: "quickshell-submap-hints"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    readonly property real screen_width: root.screen ? root.screen.width : 1920
    readonly property real screen_height: root.screen ? root.screen.height : 1080
    readonly property var screen_frame: root.screen ? ScreenFrames.layout_for(root.screen) : null
    readonly property bool drawer: scaffold.active

    // Lets the frame and the strip leave their lines out under the window, while it is mapped.
    DrawerWindowPublisher {
        screen_name: root.screen ? root.screen.name : ""
        rect: scaffold.window_rect
    }

    TransientDrawer {
        id: scaffold
        screen_frame: root.screen_frame
        screen_name: root.screen ? root.screen.name : ""
        screen_width: root.screen_width
        screen_height: root.screen_height
        side: "center"
        from_bottom: !root.on_top
        panel_width: plate.implicitWidth
        panel_height: plate.implicitHeight
        shown: root.visible
        window_width: root.width
        window_height: root.height
    }

    // Opens or folds the drawer to match `wanted`; a change mid-way reverses from where it is.
    function refresh() {
        if (!root.drawer) return;
        if (root.wanted) {
            scaffold.close_anim.stop();
            if (scaffold.progress < 1 && !scaffold.open_anim.running) scaffold.open_anim.start();
        } else {
            scaffold.open_anim.stop();
            if (scaffold.progress > 0 && !scaffold.close_anim.running) scaffold.close_anim.start();
        }
    }

    // A change of edge or of frame restarts from closed instead of sliding across.
    function restart() {
        scaffold.open_anim.stop();
        scaffold.close_anim.stop();
        scaffold.progress = 0;
        root.refresh();
    }

    onWantedChanged: root.refresh()
    onDrawerChanged: root.restart()
    onOn_topChanged: root.restart()
    Component.onCompleted: root.refresh()

    // The drawer's body uncovers the plate as it grows; floating, this is the whole window and clips nothing.
    Item {
        id: clip_box
        x: root.drawer ? scaffold.body.x : 0
        y: root.drawer ? scaffold.body.y : 0
        width: root.drawer ? scaffold.body.width : root.width
        height: root.drawer ? scaffold.body.height : root.height
        clip: root.drawer

        HintPlate {
            id: plate
            // The plate rides out with the drawer's far edge instead of staying put while the body uncovers it.
            x: root.drawer ? (clip_box.width - plate.width) / 2 : 0
            y: root.drawer && !scaffold.from_bottom ? clip_box.height - plate.height : 0
            plain: root.drawer
            width: plate.implicitWidth
            height: plate.implicitHeight
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
    }
}
