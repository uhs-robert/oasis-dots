// home/quickshell/.config/quickshell/popups/StartPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"
import "../theme"
import "../services"
import "start" as Start
import "snes" as Snes
import "../components/ps2" as Ps2

Popup {
    id: root

    popup_name: "start"
    preferred_width: root.st.status_strip ? 235 : root.st.console_views === "snes" ? 210 : 180
    footer_hint: root.confirm ? "y/Enter confirm · n/Esc back" : "j/k move · gg/G first/last · Enter run · 1-" + root.actions.length + " pick · q close"
    body_height: content.implicitHeight + 24
    jumps_enabled: !root.confirm

    readonly property var actions: ["Apps", "Style", "Lock", "Logout", "Reboot", "Power Off"]
    readonly property var keys: root.actions.map((a, i) => String(i + 1))
    readonly property var glyphs: ["󰣇", "󰏘", "󰌾", "󰍃", "󰜉", "󰐥"]
    readonly property var glyph_colors: [Theme.green, Theme.theme_secondary, root.st.text_fg, Theme.info, Theme.warning, Theme.theme_label]

    property int selected: 0
    property bool confirm: false

    readonly property bool is_open: Popups.open_name === "start"
    onIs_openChanged: if (is_open) {
        if (Popups.pending_confirm >= 0) {
            selected = Popups.pending_confirm;
            confirm = true;
            Popups.pending_confirm = -1;
        } else {
            selected = 0;
            confirm = false;
        }
    }
    search_enabled: !root.confirm
    search_rows: root.actions
    search_cursor: root.selected
    onSearch_select: index => root.selected = index
    onJump_first: root.selected = 0
    onJump_last: root.selected = root.actions.length - 1

    function choose(index) {
        selected = index;
        if (index === 0) {
            if (!Pickers.open("apps", Popups.open_anchor, Popups.open_color, Popups.open_screen_name, "start")) run(0);
        } else if (index === 1) Popups.open("style", Popups.open_anchor, Popups.open_color, Popups.open_screen_name, "start");
        else confirm = true;
    }

    function run(index) {
        if (index === 0) {
            Quickshell.execDetached(["hyprctl", "dispatch", "LayerRules.exec_without_animation('rofi -show drun -theme ~/.config/rofi/themes/oasis-start.rasi')"]);
        } else if (index === 2) {
            Quickshell.execDetached(["sh", "-c", "~/.config/hypr/scripts/lock-screen.sh"]);
        } else if (index === 3) {
            Quickshell.execDetached(["sh", "-c", "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch \"hl.dsp.exit()\""]);
        } else if (index === 4) {
            Quickshell.execDetached(["systemctl", "reboot"]);
        } else if (index === 5) {
            Quickshell.execDetached(["systemctl", "poweroff"]);
        }
        Popups.close();
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: root.confirm ? confirm_row.implicitHeight : (menu_view.active ? menu_view.implicitHeight : actions_col.implicitHeight) + (strip_loader.active ? strip_loader.height + 10 : 0)
        focus: true

        Loader {
            active: root.st.console_views === "ps2"
            anchors.fill: parent
            anchors.margins: -12
            z: -2
            sourceComponent: Ps2.Haze {}
        }

        Loader {
            active: root.st.schematic.a > 0
            visible: !root.confirm
            anchors.right: parent.right
            anchors.rightMargin: -4
            y: -4
            z: -1
            width: Style.px(90)
            sourceComponent: Schematic {
                color: root.st.schematic
            }
        }

        Keys.onPressed: event => {
            if (root.confirm) {
                if (event.key === Qt.Key_Y || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.run(root.selected);
                    event.accepted = true;
                } else if (event.key === Qt.Key_N || event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
                    root.confirm = false;
                    event.accepted = true;
                }
                return;
            }
            if (event.key === Qt.Key_J) {
                root.selected = root.wrap_index(root.selected, 1, 0, root.actions.length);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.selected = root.wrap_index(root.selected, -1, 0, root.actions.length);
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.choose(root.selected);
                event.accepted = true;
            } else if (!(event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier)) && root.keys.indexOf(event.text) >= 0) {
                root.choose(root.keys.indexOf(event.text));
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: actions_col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 4
            visible: !root.confirm && !menu_view.active

            Repeater {
                model: root.actions

                MenuRow {
                    id: row
                    required property int index
                    required property string modelData

                    Layout.fillWidth: true
                    height: Style.px(28)
                    base_radius: 6
                    selected: index === root.selected
                    key: root.keys[row.index]
                    slot: row.index + 1

                    Loader {
                        anchors.fill: parent
                        z: -1
                        sourceComponent: ({ ps2: ps2_block })[root.st.console_views] || null

                        Component {
                            id: ps2_block
                            Ps2.Block {
                                selected: row.selected
                            }
                        }
                    }

                    RowLayout {
                        anchors.left: parent.left
                        anchors.leftMargin: 8 + row.inset
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            text: root.glyphs[row.index]
                            color: row.fg(root.glyph_colors[row.index])
                            font.family: root.st.font_family
                            font.pixelSize: root.st.font_size
                        }

                        RowLabel {
                            label: row.modelData
                            color: row.fg(root.st.text_fg)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.font_size
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.choose(row.index)
                    }
                }
            }
        }

        // Console menus replace the action rows.
        Loader {
            id: menu_view
            readonly property Component view: ({ nes: nes_menu, snes: snes_menu })[root.st.console_views] || null
            active: !!view
            visible: !root.confirm
            anchors.left: parent.left
            anchors.right: parent.right
            sourceComponent: view
        }

        Component {
            id: nes_menu
            Start.NesMenu {
                popup: root
            }
        }

        Component {
            id: snes_menu
            Snes.SnesStartView {
                labels: root.actions
                keys: root.keys
                selected: root.selected
                onPicked: index => root.choose(index)
            }
        }

        Loader {
            id: strip_loader
            active: root.st.status_strip
            visible: !root.confirm
            x: -12
            y: actions_col.implicitHeight + 10
            width: parent.width + 24
            sourceComponent: StatusStrip {}
        }

        RowLayout {
            id: confirm_row
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            visible: root.confirm
            spacing: 12

            Text {
                text: root.glyphs[root.selected] + " " + root.actions[root.selected] + "?"
                color: root.glyph_colors[root.selected]
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size
            }

            Text {
                text: "Yes"
                color: Theme.ok
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.run(root.selected)
                }
            }

            Text {
                text: "No"
                color: Theme.error
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.confirm = false
                }
            }
        }
    }
}
