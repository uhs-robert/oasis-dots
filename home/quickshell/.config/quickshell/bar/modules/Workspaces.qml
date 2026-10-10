// home/quickshell/.config/quickshell/bar/modules/Workspaces.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../../theme"
import "../../services"
import "../../components"
import "../../components/ff7" as Ff7
import "../../components/gameboy" as Gameboy
import "../../components/goldeneye" as Goldeneye
import "../../components/metroid" as Metroid
import "../../components/neovim" as Neovim
import "../../components/nes" as Nes
import "../../components/oasis" as Oasis
import "../../components/ps1" as Ps1
import "../../components/ps2" as Ps2
import "../../components/snes" as Snes
import "../../components/ff7/Materia.js" as Materia

Item {
    id: root

    property string screen_name: ""
    property bool compact: false
    property int bar_height: 30

    // Final Fantasy Tactics map: an isometric tile per workspace, stretching so every app stands on it.
    readonly property bool slots: Style.workspace_art === "slots"
    // Super Mario World overworld: level dots on a dotted trail, app icons above them.
    readonly property bool map: Style.workspace_art === "map"
    // Pokemon party: a Poke Ball per workspace, the shown ones open into a party box under a cursor, the active app hopping.
    readonly property bool party: Style.workspace_art === "party"
    // GoldenEye watch dial: workspace ticks on one arc replace the pills.
    readonly property bool dial: Style.workspace_art === "dial"
    // Oasis night sky: a star per workspace on a low constellation, apps under their star.
    readonly property bool stars: Style.workspace_art === "constellation"
    // Where every plain-pill read comes from: the owning style's pills when a named set is borrowed, a plain round pill in the host's colours when "Pills" is picked over a style whose own look is an art or pill set, else the host itself. Styles with a plain "" look keep their own pills (ring, squares) under "". Style.styles holds each style in the current palette, typed like the Style exports.
    readonly property var pill_tokens: {
        const art = Style.workspace_art;
        const owner = Style.workspace_pill_owners[art];
        if (owner) return owner === Style.name ? Style : Style.resolve(Style.styles[owner]);
        if (art === "" && Style.base_active.workspace_art !== "") return Style.resolve(Object.assign({}, Style.active, Style.plain_pill_shape));
        return Style;
    }
    readonly property int party_gap: 8
    // FF7 weapon slot bar: apps are materia orbs in sockets linked in pairs.
    readonly property bool materia: Style.workspace_art === "materia"
    readonly property int slot_size: compact ? 22 : 24
    // Metroid door hatches: closed doors show their app count, the active one opens onto its apps.
    readonly property bool doors: Style.workspace_art === "doors"
    // Lualine buffers: numbered tabs with their apps, full bar height.
    readonly property bool buffers: Style.workspace_art === "buffers"
    readonly property int icon_size: materia ? (compact ? 10 : 12) : doors ? (compact ? 12 : 14) : party ? (compact ? 14 : 16) : slots ? (compact ? 15 : 17) : compact ? 16 : 19
    readonly property int pill_height: materia ? slot_size : doors ? (compact ? 26 : 30) : map ? 34 : slots ? (compact ? 26 : 30) : party ? (compact ? 22 : 26) : root.pill_tokens.bar_pill_height > 0 ? root.pill_tokens.bar_pill_height - (compact ? 4 : 0) : compact ? 20 : 22
    readonly property int tile_face: compact ? 8 : 10
    readonly property int tile_depth: compact ? 2 : 3

    implicitWidth: row.implicitWidth + (materia ? 12 : 0)
    // Dots are shorter than pills; the row keeps the pill height so it stays centered.
    implicitHeight: root.pill_tokens.bar_workspace_dot.a > 0 ? Math.max(row.implicitHeight, root.pill_height) : row.implicitHeight

    // Workspace ids Hyprland reports on this screen, read with hyprctl.
    readonly property var hypr_ids: WindowState.hypr_workspaces.filter(w => w.monitor === root.screen_name).map(w => w.id)

    readonly property var workspace_list: {
        const list = Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor && w.monitor.name === root.screen_name);
        const known = list.map(w => w.id);
        // Quickshell can miss existing workspaces (persistent ones at login) and QML cannot make it re-list them.
        for (const id of root.hypr_ids) {
            if (known.indexOf(id) < 0) list.push({ id: id, name: String(id), focused: false, active: false, monitor: { name: root.screen_name }, lastIpcObject: {} });
        }
        list.sort((a, b) => a.id - b.id);
        return list;
    }

    readonly property var workspace_by_id: root.workspace_list.reduce((map, w) => { map[w.id] = w; return map; }, ({}))

    // Pills are keyed by workspace id so a change does not rebuild the whole row.
    ListModel {
        id: pill_ids
    }

    function sync_pills() {
        const ids = root.workspace_list.map(w => w.id);
        for (let i = pill_ids.count - 1; i >= 0; i--) {
            if (ids.indexOf(pill_ids.get(i).ws_id) < 0) pill_ids.remove(i);
        }
        ids.forEach((id, i) => {
            if (i < pill_ids.count && pill_ids.get(i).ws_id === id) return;
            pill_ids.insert(i, { ws_id: id });
        });
    }

    onWorkspace_listChanged: root.sync_pills()
    Component.onCompleted: root.sync_pills()

    function class_of(toplevel) {
        if (toplevel.wayland && toplevel.wayland.appId) return toplevel.wayland.appId;
        return (toplevel.lastIpcObject && toplevel.lastIpcObject.class) || "";
    }

    function name_of(toplevel) {
        const cls = root.class_of(toplevel);
        const entry = cls ? DesktopEntries.heuristicLookup(cls) : null;
        return entry && entry.name ? entry.name : cls ? cls.split(".").pop() : "window";
    }

    // Focus the workspace then the window in one eval, holding cursor:no_warps and restoring the configured value.
    function focus_toplevel(ws_id, address) {
        if (!/^[0-9a-fA-F]+$/.test(address || "")) return;
        const lua = "local nw = hl.get_config('cursor.no_warps'); " +
            "hl.config({ cursor = { no_warps = true } }); " +
            "pcall(function() " +
            "hl.dispatch(hl.dsp.focus({ workspace = '" + ws_id + "' })); " +
            "hl.dispatch(hl.dsp.focus({ window = 'address:0x" + address + "' })) " +
            "end); " +
            "hl.config({ cursor = { no_warps = nw == true } })";
        Quickshell.execDetached(["hyprctl", "eval", lua]);
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
        spacing: root.materia ? (root.compact ? 10 : 12) : root.doors ? 2 : root.map ? 8 : root.slots || root.party ? 6 : root.pill_tokens.bar_workspace_gap > 0 ? root.pill_tokens.bar_workspace_gap - (root.compact ? 2 : 0) : root.compact ? 6 : 8

        Loader {
            active: root.dial
            visible: active
            sourceComponent: Goldeneye.WatchDial {
                host: root
                workspaces: root.workspace_list
                compact: root.compact
            }
        }

        Loader {
            active: root.stars
            visible: active
            sourceComponent: Oasis.Constellation {
                host: root
                workspaces: root.workspace_list
                compact: root.compact
                bar_height: root.bar_height
            }
        }

        Loader {
            active: root.buffers
            visible: active
            sourceComponent: Neovim.BufferLine {
                host: root
                workspaces: root.workspace_list
                compact: root.compact
                bar_height: root.bar_height
            }
        }

        Repeater {
            model: root.dial || root.stars || root.buffers ? null : pill_ids

            Rectangle {
                id: pill
                required property int ws_id
                readonly property var modelData: root.workspace_by_id[pill.ws_id] || ({ id: pill.ws_id, name: String(pill.ws_id), focused: false, active: false, lastIpcObject: {} })

                readonly property bool is_empty: pill.toplevels.length === 0
                // Pill art that draws its own shape; the style's pill geometry and overlays (diamond, square, ring, materia orb) would distort it when borrowed.
                readonly property bool art: root.materia || root.doors || root.party || root.map || root.slots || pill.qblock || pill.ps2
                readonly property bool diamond: root.pill_tokens.bar_workspace_diamond && is_empty && !pill.art
                readonly property bool map: root.map
                readonly property int glyph: map ? (modelData.focused ? 17 : 14) : root.icon_size
                // Mario ? blocks; the focused workspace is the one already hit.
                readonly property bool qblock: Style.workspace_art === "qblock"
                readonly property bool ps2: Style.workspace_art === "ps2"
                readonly property var toplevels: WindowState.windows_on(modelData)
                readonly property int cursor_gap: root.party && modelData.focused ? root.party_gap : 0
                readonly property bool ball: root.party && (is_empty || !modelData.active)
                property bool hop: false
                // Plain pills: the style's own art is drawn by none of the branches above.
                readonly property bool plain: !root.materia && !root.doors && !pill.qblock && !pill.ps2 && !root.slots && !pill.map && !root.party && !pill.diamond
                readonly property bool dot: pill.plain && pill.is_empty && !pill.modelData.active && root.pill_tokens.bar_workspace_dot.a > 0

                // Hovered dots grow and light a core, the only hint they can be clicked.
                readonly property bool dot_hovered: pill_hover.hovered || dot_hover.hovered
                property real dot_size: pill.dot_hovered ? 11 : 7
                Behavior on dot_size {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }

                height: pill.dot ? 11 : root.pill_height
                y: (root.pill_height - height) / 2
                width: root.materia ? (is_empty ? root.slot_size : icons.implicitWidth) : root.doors ? (modelData.active && !is_empty ? icons.implicitWidth + height - 4 : height) : root.party ? cursor_gap + (pill.ball ? 16 : icons.implicitWidth + 10) : pill.map ? Math.max(22, icons.implicitWidth + 8) : root.slots ? (is_empty ? root.tile_face * 2 + 4 : icons.implicitWidth + root.tile_face + 6) : is_empty ? height : icons.implicitWidth + (modelData.active ? 22 : 12) + root.pill_tokens.bar_pill_pad * 2
                radius: pill.map || root.party || root.slots ? 0 : (root.pill_tokens.bar_pill_square && !pill.art) || pill.qblock ? 0 : height / 2
                rotation: pill.diamond ? 45 : 0
                scale: pill.diamond ? 0.75 : 1
                antialiasing: pill.diamond || radius > 0
                color: root.materia || root.doors || pill.qblock || pill.ps2 || root.slots || pill.map || root.party ? "transparent" : pill.dot ? "transparent" : modelData.focused ? root.pill_tokens.bar_workspace_focused : modelData.active ? root.pill_tokens.bar_workspace_active : root.pill_tokens.bar_workspace_idle
                border.width: !pill.art && root.pill_tokens.bar_workspace_ring.a > 0 && !(root.pill_tokens.bar_workspace_diamond && !is_empty && modelData.focused) ? 1 : 0
                border.color: root.pill_tokens.bar_workspace_ring

                Behavior on width {
                    NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
                }
                Behavior on color {
                    ColorAnimation { duration: 280; easing.type: Easing.InOutCubic }
                }

                // Console pill art: NES ? blocks, PS1 Tactics tiles, PS2 save cubes and lit blocks, SNES map dots, Game Boy Poke Balls and party rows.
                Loader {
                    anchors.fill: parent
                    z: pill.map ? 1 : 0

                    Component {
                        id: metroid_door
                        Metroid.DoorHatch {
                            open: pill.modelData.active
                            lit: pill.modelData.focused
                            empty: pill.is_empty
                            count: pill.toplevels.length
                        }
                    }

                    sourceComponent: root.materia ? ff7_slots : root.doors ? metroid_door : pill.qblock ? nes_qblock : root.slots ? ps1_card : pill.ps2 ? (pill.is_empty ? ps2_cube : ps2_block) : pill.map ? snes_dot : root.party ? gb_party : null

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

                            Gameboy.PokeBall {
                                id: ball
                                visible: pill.ball
                                x: pill.cursor_gap + 1
                                anchors.verticalCenter: parent.verticalCenter
                                full: !pill.is_empty
                                lit: pill.modelData.focused

                                SequentialAnimation on rotation {
                                    running: ball.visible && pill.modelData.urgent === true
                                    loops: Animation.Infinite
                                    alwaysRunToEnd: true
                                    NumberAnimation { to: -18; duration: 90 }
                                    NumberAnimation { to: 18; duration: 180 }
                                    NumberAnimation { to: 0; duration: 90 }
                                    PauseAnimation { duration: 500 }
                                }
                            }

                            Gameboy.PartyBox {
                                visible: !pill.ball
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

                Rectangle {
                    visible: pill.plain && pill.modelData.focused && root.pill_tokens.bar_workspace_shade.a > 0
                    anchors.fill: parent
                    radius: pill.radius
                    gradient: Gradient {
                        GradientStop { position: 0; color: root.pill_tokens.bar_workspace_shade }
                        GradientStop { position: 1; color: root.pill_tokens.bar_workspace_focused }
                    }
                }

                Sheen {
                    color_top: pill.plain && !pill.dot ? root.pill_tokens.sheen : "transparent"
                    corner: pill.radius
                }

                // The dot is drawn inside a fixed 11px slot, so growing it moves nothing else.
                Rectangle {
                    visible: pill.dot
                    anchors.centerIn: parent
                    width: pill.dot_size
                    height: width
                    radius: width / 2
                    color: root.pill_tokens.bar_workspace_dot
                }

                Rectangle {
                    visible: pill.dot && opacity > 0
                    anchors.centerIn: parent
                    width: 5
                    height: 5
                    radius: 2.5
                    color: root.pill_tokens.bar_workspace_focused
                    opacity: pill.dot_hovered ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                }

                MateriaOrb {
                    visible: pill.modelData.focused && root.pill_tokens.materia.workspace !== undefined && !pill.art
                    anchors.fill: parent
                    radius: pill.radius
                    glow: false
                    color: visible ? root.pill_tokens.materia.workspace : "transparent"
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: pill.cursor_gap
                    radius: parent.radius
                    color: root.party ? Style.pixel_shades[3] : Theme.fg_core
                    opacity: !root.slots && !root.materia && !pill.dot && !pill.modelData.active && pill_hover.hovered ? 0.1 : 0

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

                Timer {
                    running: root.party && pill.modelData.focused && !pill.ball && Power.on_ac
                    interval: 500
                    repeat: true
                    onTriggered: pill.hop = !pill.hop
                    onRunningChanged: if (!running) pill.hop = false
                }

                // A dot's hit area: the capsule's height, out to half the gap on each side.
                Item {
                    visible: pill.dot
                    x: -row.spacing / 2
                    y: (pill.height - height) / 2
                    width: pill.width + row.spacing
                    height: root.bar_height - Style.bar_capsule

                    HoverHandler {
                        id: dot_hover
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = '" + pill.modelData.id + "' })")
                    }
                }

                Row {
                    id: icons
                    visible: (!root.doors || pill.modelData.active) && !pill.ball
                    anchors.centerIn: pill.map || root.slots ? undefined : parent
                    anchors.horizontalCenter: pill.map || root.slots ? parent.horizontalCenter : undefined
                    anchors.top: pill.map || root.slots ? parent.top : undefined
                    anchors.topMargin: root.slots ? pill.height - root.tile_depth - root.tile_face / 2 + 1 - pill.glyph : pill.modelData.focused ? 1 : 3
                    anchors.horizontalCenterOffset: pill.cursor_gap / 2
                    spacing: root.materia ? 6 : pill.map ? 1 : 2

                    Repeater {
                        model: pill.toplevels

                        WorkspaceIcon {
                            id: icon_item
                            required property int index

                            host: root
                            workspace_id: pill.modelData.id
                            glyph: pill.glyph
                            icon_opacity: pill.map && !pill.modelData.focused ? 0.6 : 1
                            width: root.materia ? root.slot_size : pill.glyph + (root.doors || root.slots || pill.map || root.party ? 0 : 4)
                            height: width
                            transform: Translate { y: pill.hop && Hyprland.activeToplevel === icon_item.modelData ? -2 : 0 }

                            Ff7.MateriaSlot {
                                visible: root.materia
                                anchors.fill: parent
                                lit: pill.modelData.focused
                                raised: pill.modelData.active || pill_hover.hovered
                                color: visible ? Style.materia_palette.days[Materia.slot_names(pill.toplevels.map(t => root.class_of(t)))[icon_item.index]] || "transparent" : "transparent"
                            }
                        }
                    }
                }
            }
        }
    }
}
