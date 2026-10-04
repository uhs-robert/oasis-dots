// home/quickshell/.config/quickshell/components/picker/TmuxTargets.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../services"

// tmux dressing for the Terminal picker skin: display-panes digits and a hyprctl clients card on
// windows, a status bar across the bottom, and a copy-mode selection rect in region mode.
Item {
    id: root

    required property string screen_name
    required property rect sel
    required property bool mine
    required property bool target_mode
    required property point origin

    readonly property bool window_mode: Screenshot.mode === "window"
    readonly property bool screen_mode: Screenshot.mode === "screen"
    readonly property bool region_mode: Screenshot.mode === "region"
    // {gi, label} for windows on this screen, gi the global index into Screenshot.targets.
    readonly property var win_entries: {
        if (!root.window_mode) return [];
        const out = [];
        for (let i = 0; i < Screenshot.targets.length; i++) {
            if (Screenshot.targets[i].screen === root.screen_name) out.push({ gi: i, label: Screenshot.targets[i].label });
        }
        return out;
    }
    property string clock_text: TimeFormat.format(new Date())

    visible: root.mine || root.target_mode

    Timer {
        interval: 30000
        running: root.screen_mode && root.target_mode
        repeat: true
        onTriggered: root.clock_text = TimeFormat.format(new Date())
    }

    Repeater {
        model: root.window_mode && Screenshot.phase === "select" ? Screenshot.targets : []

        Item {
            id: win
            required property var modelData
            required property int index
            readonly property bool is_target: win.index === Screenshot.target_index
            visible: win.modelData.screen === root.screen_name
            x: win.modelData.rect.x
            y: win.modelData.rect.y
            width: win.modelData.rect.width
            height: win.modelData.rect.height

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: win.is_target ? 2 : 1
                border.color: win.is_target ? Theme.green : Qt.alpha(Theme.fg_dim, 0.6)
            }

            Text {
                anchors.centerIn: parent
                text: Style.picker_hint_keys.charAt(win.index)
                color: win.is_target ? Theme.red : Theme.blue
                font.family: Style.mono_font
                font.bold: true
                font.pixelSize: 96
            }
        }
    }

    Item {
        id: hypr_card
        readonly property var t: root.window_mode && Screenshot.targets[Screenshot.target_index] ? Screenshot.targets[Screenshot.target_index] : null
        readonly property real card_w: 236
        visible: root.window_mode && root.mine && Screenshot.phase === "select" && hypr_card.t !== null && hypr_card.t.screen === root.screen_name
        x: Math.max(0, Math.min(root.width - hypr_card.card_w, hypr_card.t ? hypr_card.t.rect.x + hypr_card.t.rect.width : 0))
        y: Math.max(0, Math.min(root.height - hypr_card.height, hypr_card.t ? hypr_card.t.rect.y + hypr_card.t.rect.height : 0))
        width: hypr_card.card_w
        height: hypr_card.t ? card_col.implicitHeight + 20 : 0

        Rectangle {
            anchors.fill: parent
            color: Theme.bg_crust
            border.width: 1
            border.color: Theme.green
        }

        Rectangle {
            x: hypr_title.x - 3
            y: hypr_title.y
            width: hypr_title.implicitWidth + 6
            height: hypr_title.implicitHeight
            color: Theme.bg_crust
        }

        Text {
            id: hypr_title
            x: 10
            y: -hypr_title.implicitHeight / 2
            text: "hyprctl clients"
            color: Theme.green
            font.family: Style.mono_font
            font.pixelSize: 11
        }

        Column {
            id: card_col
            x: 10
            y: 10
            width: parent.width - 20
            spacing: 2

            Row {
                spacing: 4
                Text {
                    text: "class:"
                    color: Theme.fg_dim
                    font.family: Style.mono_font
                    font.pixelSize: 12
                }
                Text {
                    text: hypr_card.t ? hypr_card.t.label : ""
                    color: Theme.fg_strong
                    font.family: Style.mono_font
                    font.pixelSize: 12
                }
            }

            Row {
                spacing: 4
                Text {
                    text: "at:"
                    color: Theme.fg_dim
                    font.family: Style.mono_font
                    font.pixelSize: 12
                }
                Text {
                    text: hypr_card.t ? Math.round(root.origin.x + hypr_card.t.rect.x) + "," + Math.round(root.origin.y + hypr_card.t.rect.y) : ""
                    color: Theme.fg_strong
                    font.family: Style.mono_font
                    font.pixelSize: 12
                }
            }

            Row {
                spacing: 4
                Text {
                    text: "size:"
                    color: Theme.fg_dim
                    font.family: Style.mono_font
                    font.pixelSize: 12
                }
                Text {
                    text: hypr_card.t ? Math.round(hypr_card.t.rect.width) + "," + Math.round(hypr_card.t.rect.height) : ""
                    color: Theme.fg_strong
                    font.family: Style.mono_font
                    font.pixelSize: 12
                }
            }
        }
    }

    Rectangle {
        visible: root.mine && root.screen_mode && Screenshot.phase === "select"
        x: 0
        y: 0
        width: root.width
        height: root.height - 20
        color: "transparent"
        border.width: 2
        border.color: Theme.green
    }

    Rectangle {
        id: status_bar
        visible: (root.window_mode || root.screen_mode) && root.target_mode && Screenshot.phase === "select"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 20
        color: Theme.green

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                text: "[main]"
                color: Theme.bg_core
                font.bold: true
                font.family: Style.mono_font
                font.pixelSize: 11
            }

            Repeater {
                model: root.window_mode ? root.win_entries : []

                Item {
                    id: win_entry
                    required property var modelData
                    readonly property bool active: win_entry.modelData.gi === Screenshot.target_index
                    width: entry_text.implicitWidth + (win_entry.active ? 8 : 0)
                    height: 16

                    Rectangle {
                        visible: win_entry.active
                        anchors.fill: parent
                        color: Theme.bg_core
                    }

                    Text {
                        id: entry_text
                        anchors.centerIn: parent
                        text: Style.picker_hint_keys.charAt(win_entry.modelData.gi) + ":" + win_entry.modelData.label + (win_entry.active ? "*" : "")
                        color: win_entry.active ? Theme.green : Theme.bg_core
                        font.bold: win_entry.active
                        font.family: Style.mono_font
                        font.pixelSize: 11
                    }
                }
            }

            Repeater {
                model: root.screen_mode ? Screenshot.targets : []

                Item {
                    id: scr_entry
                    required property var modelData
                    required property int index
                    readonly property bool active: scr_entry.index === Screenshot.target_index
                    width: scr_text.implicitWidth + (scr_entry.active ? 8 : 0)
                    height: 16

                    Rectangle {
                        visible: scr_entry.active
                        anchors.fill: parent
                        color: Theme.bg_core
                    }

                    Text {
                        id: scr_text
                        anchors.centerIn: parent
                        text: Style.picker_hint_keys.charAt(scr_entry.index) + ":" + scr_entry.modelData.label + (scr_entry.active ? "*" : "")
                        color: scr_entry.active ? Theme.green : Theme.bg_core
                        font.bold: scr_entry.active
                        font.family: Style.mono_font
                        font.pixelSize: 11
                    }
                }
            }
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: root.window_mode ? "display-panes" : "\"" + Math.round(root.width) + "x" + Math.round(root.height) + "\" " + root.clock_text
            color: Theme.bg_core
            font.family: Style.mono_font
            font.pixelSize: 11
        }
    }

    Rectangle {
        visible: root.mine && root.region_mode && (Screenshot.phase === "select" || Screenshot.phase === "toolbar")
        x: root.sel.x
        y: root.sel.y
        width: root.sel.width
        height: root.sel.height
        color: Qt.alpha(Theme.ui_match_bg, 0.3)
        border.width: 1
        border.color: Theme.ui_match_bg
    }
}
