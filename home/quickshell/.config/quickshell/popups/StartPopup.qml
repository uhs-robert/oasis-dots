// home/quickshell/.config/quickshell/popups/StartPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"
import "../theme"
import "../services"

Popup {
    id: root

    popup_name: "start"
    preferred_width: 180
    implicitHeight: content.implicitHeight + 24

    readonly property var actions: ["Apps", "Lock", "Logout", "Reboot", "Power Off"]
    readonly property var glyphs: ["󰣇", "󰌾", "󰍃", "󰜉", "󰐥"]
    readonly property var glyph_colors: [Theme.green, Theme.fg_core, Theme.info, Theme.warning, Theme.theme_label]

    property int selected: 0
    property bool confirm: false

    readonly property bool is_open: Popups.open_name === "start"
    onIs_openChanged: if (is_open) {
        selected = 0;
        confirm = false;
    }

    function choose(index) {
        selected = index;
        if (index === 0) run(0);
        else confirm = true;
    }

    function run(index) {
        if (index === 0) {
            Quickshell.execDetached(["hyprctl", "dispatch", "LayerRules.exec_without_animation('rofi -show drun -theme ~/.config/rofi/themes/oasis-start.rasi')"]);
        } else if (index === 1) {
            Quickshell.execDetached(["sh", "-c", "~/.config/hypr/scripts/hyprlock-screenshot.lua"]);
        } else if (index === 2) {
            Quickshell.execDetached(["sh", "-c", "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch \"hl.dsp.exit()\""]);
        } else if (index === 3) {
            Quickshell.execDetached(["systemctl", "reboot"]);
        } else if (index === 4) {
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
        implicitHeight: root.confirm ? confirm_row.implicitHeight : actions_col.implicitHeight
        focus: true

        Keys.onPressed: event => {
            if (root.confirm) {
                if (event.key === Qt.Key_Y || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.run(root.selected);
                    event.accepted = true;
                } else if (event.key === Qt.Key_N || event.key === Qt.Key_Escape) {
                    root.confirm = false;
                    event.accepted = true;
                }
                return;
            }
            if (event.key === Qt.Key_J) {
                root.selected = (root.selected + 1) % root.actions.length;
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.selected = (root.selected - 1 + root.actions.length) % root.actions.length;
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.choose(root.selected);
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: actions_col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 4
            visible: !root.confirm

            Repeater {
                model: root.actions

                Rectangle {
                    id: row
                    required property int index
                    required property string modelData

                    Layout.fillWidth: true
                    height: 28
                    radius: 6
                    color: index === root.selected ? Theme.bg_surface : "transparent"

                    RowLayout {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            text: root.glyphs[row.index]
                            color: root.glyph_colors[row.index]
                            font.family: Theme.font_family
                            font.pixelSize: Theme.popup_font_size
                        }

                        Text {
                            text: row.modelData
                            color: Theme.fg_core
                            font.family: Theme.font_family
                            font.pixelSize: Theme.popup_font_size
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.choose(row.index)
                    }
                }
            }
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
                font.family: Theme.font_family
                font.pixelSize: Theme.popup_font_size
            }

            Text {
                text: "Yes"
                color: Theme.ok
                font.family: Theme.font_family
                font.pixelSize: Theme.popup_font_size

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.run(root.selected)
                }
            }

            Text {
                text: "No"
                color: Theme.error
                font.family: Theme.font_family
                font.pixelSize: Theme.popup_font_size

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.confirm = false
                }
            }
        }
    }
}
