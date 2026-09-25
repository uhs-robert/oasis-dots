// home/quickshell/.config/quickshell/bar/modules/Workspaces.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import "../../theme"
import "../../services"
import "../../components"
import "../../components/ff7" as Ff7
import "../../components/gameboy" as Gameboy
import "../../components/nes" as Nes
import "../../components/ps1" as Ps1
import "../../components/ps2" as Ps2
import "../../components/snes" as Snes
import "../../components/ff7/Materia.js" as Materia

Item {
    id: root

    property string screen_name: ""
    property bool compact: false

    // Final Fantasy Tactics map: an isometric tile per workspace, stretching so every app stands on it.
    readonly property bool slots: Style.console_views === "ps1"
    // Super Mario World overworld: level dots on a dotted trail, app icons above them.
    readonly property bool map: Style.console_views === "snes"
    // Pokemon party rows: a double-bordered box per workspace, the focused one pointed at by a cursor.
    readonly property bool party: Style.controller === "gameboy"
    readonly property int party_gap: 8
    // FF7 weapon slot bar: apps are materia orbs in sockets linked in pairs.
    readonly property bool materia: Style.workspace_art === "materia"
    readonly property int slot_size: compact ? 22 : 24
    readonly property int icon_size: materia ? (compact ? 10 : 12) : party ? (compact ? 14 : 16) : slots ? (compact ? 15 : 17) : compact ? 16 : 19
    readonly property int pill_height: materia ? slot_size : map ? 34 : slots ? (compact ? 26 : 30) : party ? (compact ? 22 : 26) : compact ? 20 : 22
    readonly property int tile_face: compact ? 8 : 10
    readonly property int tile_depth: compact ? 2 : 3

    implicitWidth: row.implicitWidth + (materia ? 12 : 0)
    implicitHeight: row.implicitHeight

    readonly property var workspace_list: {
        const list = Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor && w.monitor.name === root.screen_name);
        list.sort((a, b) => a.id - b.id);
        return list;
    }

    function icon_for(cls) {
        const entry = DesktopEntries.heuristicLookup(cls);
        return Quickshell.iconPath(entry ? entry.icon : cls, "application-x-executable");
    }

    function class_of(toplevel) {
        if (toplevel.wayland && toplevel.wayland.appId) return toplevel.wayland.appId;
        return (toplevel.lastIpcObject && toplevel.lastIpcObject.class) || "";
    }

    function name_of(toplevel) {
        const cls = root.class_of(toplevel);
        const entry = cls ? DesktopEntries.heuristicLookup(cls) : null;
        return entry && entry.name ? entry.name : cls ? cls.split(".").pop() : "window";
    }

    // Mirrors hypr-focus-workspaces.lua: focus the workspace then the window, holding cursor:no_warps.
    function focus_toplevel(ws_id, address) {
        Hyprland.dispatch("hl.dsp.focus({ workspace = '" + ws_id + "' })");
        const cmd = "already=$(hyprctl getoption cursor:no_warps -j | grep -o '\"bool\": *true'); " +
            "if [ -z \"$already\" ]; then hyprctl eval \"hl.config({ cursor = { no_warps = true } })\" >/dev/null 2>&1; fi; " +
            "hyprctl dispatch \"hl.dsp.focus({ window = 'address:0x" + address + "' })\"; " +
            "if [ -z \"$already\" ]; then hyprctl eval \"hl.config({ cursor = { no_warps = false } })\" >/dev/null 2>&1; fi";
        Quickshell.execDetached(["sh", "-c", cmd]);
    }

    function close_toplevel(address) {
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.close({ window = 'address:0x" + address + "' })"]);
    }

    // The workspace/toplevel models can lag behind these events; nudge a resync.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (["openwindow", "closewindow", "movewindow", "workspace", "focusedmon"].includes(event.name)) {
                Hyprland.refreshToplevels();
                Hyprland.refreshWorkspaces();
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            Hyprland.dispatch("hl.dsp.focus({ workspace = '" + (wheel.angleDelta.y > 0 ? "e-1" : "e+1") + "' })");
        }
    }

    Item {
        id: trail
        visible: root.map
        x: -8
        y: 24
        width: Math.max(0, row.width - 3)
        height: 2

        Repeater {
            model: root.map ? Math.floor((trail.width + 3) / 5) : 0

            Rectangle {
                required property int index
                x: index * 5
                width: 2
                height: 2
                color: Qt.tint(Theme.bg_core, Qt.alpha(Theme.theme_secondary_strong, 0.75))
            }
        }
    }

    Ff7.WeaponBar {
        visible: root.materia
        y: -2
        width: row.width + 12
        height: row.height + 4
    }

    Row {
        id: row
        x: root.materia ? 6 : 0
        spacing: root.materia ? (root.compact ? 10 : 12) : root.map ? 8 : root.slots || root.party ? 6 : root.compact ? 6 : 8

        Repeater {
            model: root.workspace_list

            Rectangle {
                id: pill
                required property var modelData

                readonly property bool is_empty: modelData.toplevels.values.length === 0
                readonly property bool diamond: Style.bar_workspace_diamond && is_empty && !root.map && !root.party && !root.slots
                readonly property bool map: root.map
                readonly property int glyph: map ? (modelData.focused ? 17 : 14) : root.icon_size
                // Mario ? blocks; the focused workspace is the one already hit.
                readonly property bool qblock: Style.console_views === "nes"
                readonly property bool ps2: Style.console_views === "ps2"
                readonly property var toplevels: modelData.toplevels.values
                readonly property int cursor_gap: root.party && modelData.focused ? root.party_gap : 0

                height: root.pill_height
                width: root.materia ? (is_empty ? root.slot_size : icons.implicitWidth) : root.party ? cursor_gap + (is_empty ? height : icons.implicitWidth + 10) : pill.map ? Math.max(22, icons.implicitWidth + 8) : root.slots ? (is_empty ? root.tile_face * 2 + 4 : icons.implicitWidth + root.tile_face + 6) : is_empty ? height : icons.implicitWidth + (modelData.active ? 22 : 12)
                radius: pill.map || root.party || root.slots ? 0 : Style.bar_pill_square || pill.qblock ? 0 : height / 2
                rotation: pill.diamond ? 45 : 0
                scale: pill.diamond ? 0.75 : 1
                antialiasing: pill.diamond || radius > 0
                color: root.materia || pill.qblock || pill.ps2 || root.slots || pill.map || root.party ? "transparent" : modelData.focused ? Style.bar_workspace_focused : modelData.active ? Style.bar_workspace_active : Style.bar_workspace_idle
                border.width: !root.materia && !root.slots && !pill.map && !root.party && Style.bar_workspace_ring.a > 0 && !(Style.bar_workspace_diamond && !is_empty && modelData.focused) ? 1 : 0
                border.color: Style.bar_workspace_ring

                Behavior on width {
                    NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
                }
                Behavior on color {
                    ColorAnimation { duration: 280; easing.type: Easing.InOutCubic }
                }

                // Console pill art: NES ? blocks, PS1 Tactics tiles, PS2 save cubes and lit blocks, SNES map dots, Game Boy party rows.
                Loader {
                    anchors.fill: parent
                    z: pill.map ? 1 : 0
                    sourceComponent: root.materia ? ff7_slots : pill.qblock ? nes_qblock : root.slots ? ps1_card : pill.ps2 ? (pill.is_empty ? ps2_cube : ps2_block) : pill.map ? snes_dot : root.party ? gb_party : null

                    Component {
                        id: ff7_slots
                        Ff7.MateriaLinks {
                            count: pill.toplevels.length
                            slot: root.slot_size
                            spacing: icons.spacing
                            lit: pill.modelData.focused
                            raised: pill.modelData.active || pill_hover.hovered
                        }
                    }

                    Component {
                        id: gb_party
                        Item {
                            Gameboy.PartyCursor {
                                visible: pill.modelData.focused
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Gameboy.PartyBox {
                                x: pill.cursor_gap
                                width: parent.width - pill.cursor_gap
                                height: parent.height
                                selected: pill.modelData.focused
                            }
                        }
                    }

                    Component {
                        id: snes_dot
                        Item {
                            Snes.MapDot {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 19
                                selected: pill.modelData.focused
                                empty: pill.is_empty
                            }

                            Snes.MapStar {
                                visible: pill.modelData.focused
                                x: pill.is_empty ? parent.width / 2 + 5 : icons.x + icons.width - 3
                                y: 0
                            }
                        }
                    }

                    Component {
                        id: ps1_card
                        Item {
                            Ps1.TacticsTile {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                face: root.tile_face
                                depth: root.tile_depth
                                selected: pill.modelData.focused
                                empty: pill.is_empty
                                hovered: !pill.modelData.active && pill_hover.hovered
                                seams: {
                                    const out = [];
                                    for (let i = 1; i < pill.toplevels.length; i++)
                                        out.push(icons.x + i * (pill.glyph + icons.spacing) - icons.spacing / 2);
                                    return out;
                                }
                            }
                        }
                    }

                    Component {
                        id: nes_qblock
                        Nes.QBlock {
                            kind: pill.modelData.focused ? "hit" : "q"
                            mark: pill.is_empty
                        }
                    }

                    Component {
                        id: ps2_cube
                        Item {
                            Ps2.SaveCube {
                                anchors.centerIn: parent
                                width: Math.round(pill.height * 0.72)
                                color: pill.modelData.focused ? Theme.theme_primary_light : Theme.theme_primary
                                selected: pill.modelData.focused
                                opacity: pill.modelData.focused || pill.modelData.active ? 1 : 0.6
                            }
                        }
                    }

                    Component {
                        id: ps2_block
                        Ps2.Block {
                            radius: pill.height / 2
                            selected: pill.modelData.focused
                            opacity: pill.modelData.focused || pill.modelData.active ? 1 : 0.7
                        }
                    }
                }

                MateriaOrb {
                    visible: pill.modelData.focused && Style.materia.workspace !== undefined && !root.materia
                    anchors.fill: parent
                    radius: pill.radius
                    glow: false
                    color: visible ? Style.materia.workspace : "transparent"
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: pill.cursor_gap
                    radius: parent.radius
                    color: root.party ? Style.shade_3 : Theme.fg_core
                    opacity: !root.slots && !root.materia && !pill.modelData.active && pill_hover.hovered ? 0.1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = '" + pill.modelData.id + "' })")
                }

                HoverHandler {
                    id: pill_hover
                }

                Row {
                    id: icons
                    anchors.centerIn: pill.map || root.slots ? undefined : parent
                    anchors.horizontalCenter: pill.map || root.slots ? parent.horizontalCenter : undefined
                    anchors.top: pill.map || root.slots ? parent.top : undefined
                    anchors.topMargin: root.slots ? pill.height - root.tile_depth - root.tile_face / 2 + 1 - pill.glyph : pill.modelData.focused ? 1 : 3
                    anchors.horizontalCenterOffset: pill.cursor_gap / 2
                    spacing: root.materia ? 6 : pill.map ? 1 : 2

                    Repeater {
                        model: pill.toplevels

                        Item {
                            id: icon_item
                            required property var modelData
                            required property int index

                            width: root.materia ? root.slot_size : pill.glyph + (root.slots || pill.map || root.party ? 0 : 4)
                            height: width

                            Ff7.MateriaSlot {
                                visible: root.materia
                                anchors.fill: parent
                                lit: pill.modelData.focused
                                raised: pill.modelData.active || pill_hover.hovered
                                color: visible ? (Style.materia.days || {})[Materia.slot_names(pill.toplevels.map(t => root.class_of(t)))[icon_item.index]] || "transparent" : "transparent"
                            }

                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: pill.glyph
                                opacity: pill.map && !pill.modelData.focused ? 0.6 : 1
                                source: root.icon_for(root.class_of(icon_item.modelData))
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.LeftButton) {
                                        root.focus_toplevel(pill.modelData.id, icon_item.modelData.address);
                                    } else if (mouse.button === Qt.MiddleButton) {
                                        root.close_toplevel(icon_item.modelData.address);
                                    }
                                }
                            }

                            HoverHandler {
                                onHoveredChanged: {
                                    if (hovered) Tooltip.show(icon_item, icon_item.modelData.title, root.name_of(icon_item.modelData));
                                    else Tooltip.hide(icon_item);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
