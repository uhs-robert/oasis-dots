// home/quickshell/.config/quickshell/components/picker/targets/Duckhunt.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../.."
import ".."

// Duck Hunt dressing for the window/screen/region target: a white frame with a dark outer
// ring around the current pick, duck markers on windows, and a HUD row of NES-box readouts.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property rect sel
    required property bool mine
    required property bool target_mode

    readonly property bool full: Screenshot.mode === "screen"
    readonly property bool region: Screenshot.mode === "region"
    readonly property bool window: root.target_mode && !root.full
    readonly property real tx: root.sel.x
    readonly property real ty: root.sel.y
    readonly property real tw: root.sel.width
    readonly property real th: root.sel.height
    readonly property int inset: root.full ? 8 : 0
    readonly property real fx: root.tx + root.inset
    readonly property real fy: root.ty + root.inset
    readonly property real fw: root.tw - root.inset * 2
    readonly property real fh: root.th - root.inset * 2
    readonly property string cur_label: {
        const t = Screenshot.targets[Screenshot.target_index];
        return t ? t.label : "";
    }
    // Window mode lists only this screen's targets; screen mode lists every output.
    readonly property var list_items: {
        if (!root.window && !root.full) return [];
        const out = [];
        for (let i = 0; i < Screenshot.targets.length; i++) {
            const t = Screenshot.targets[i];
            if (root.window && t.screen !== root.screen_name) continue;
            out.push({ i: i, label: t.label, rect: t.rect });
        }
        return out;
    }
    readonly property var capped_items: root.list_items.slice(0, 10)

    Rectangle {
        visible: root.mine
        x: root.fx - 2
        y: root.fy - 2
        width: root.fw + 4
        height: root.fh + 4
        color: "transparent"
        border.width: 2
        border.color: Theme.bg_shadow
    }

    Rectangle {
        visible: root.mine
        x: root.fx
        y: root.fy
        width: root.fw
        height: root.fh
        color: "transparent"
        border.width: 3
        border.color: Theme.fg_strong
    }

    Repeater {
        model: root.window && Screenshot.phase === "select" ? root.capped_items : []

        DuckIcon {
            id: marker
            required property var modelData
            readonly property real marker_w: 12 * marker.scale
            readonly property real marker_h: 10 * marker.scale
            x: Math.max(0, Math.min(root.width - marker.marker_w, marker.modelData.rect.x))
            y: Math.max(0, Math.min(root.height - marker.marker_h, marker.modelData.rect.y))
            scale: 1.6
            transformOrigin: Item.TopLeft
            fill: Theme.fg_muted
        }
    }

    Item {
        id: hud
        visible: (root.window || root.full) && root.target_mode
        x: 24
        y: root.height - hud.height - 22
        width: root.width - 48
        height: 40

        Rectangle {
            id: r_box
            x: 0
            y: 0
            height: parent.height
            width: r_row.implicitWidth + 16
            radius: 6
            color: Theme.bg_shadow
            border.width: 3
            border.color: Theme.green

            Row {
                id: r_row
                anchors.centerIn: parent

                Text {
                    text: "R="
                    color: Theme.bright_green
                    font.family: Style.font_family
                    font.pixelSize: 10
                }

                Text {
                    text: String(Screenshot.target_index + 1)
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: 10
                }
            }
        }

        Rectangle {
            id: shot_box
            x: r_box.x + r_box.width + 8
            y: 0
            height: parent.height
            width: shot_col.implicitWidth + 16
            radius: 6
            color: Theme.bg_shadow
            border.width: 3
            border.color: Theme.green

            Column {
                id: shot_col
                anchors.centerIn: parent
                spacing: 2

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 3

                    Repeater {
                        model: 3

                        Rectangle {
                            width: 5
                            height: 11
                            topLeftRadius: 2
                            topRightRadius: 2
                            color: Theme.bright_yellow
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "SHOT"
                    color: Theme.bright_green
                    font.family: Style.font_family
                    font.pixelSize: 10
                }
            }
        }

        Rectangle {
            id: score_box
            x: parent.width - width
            y: 0
            height: parent.height
            width: score_col.implicitWidth + 16
            radius: 6
            color: Theme.bg_shadow
            border.width: 3
            border.color: Theme.green

            Column {
                id: score_col
                anchors.centerIn: parent
                spacing: 2

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Math.round(root.tw) + "x" + Math.round(root.th)
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: 10
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "SCORE"
                    color: Theme.bright_green
                    font.family: Style.font_family
                    font.pixelSize: 10
                }
            }
        }

        Rectangle {
            id: hit_box
            x: shot_box.x + shot_box.width + 8
            y: 0
            width: Math.max(0, score_box.x - 8 - hit_box.x)
            height: parent.height
            radius: 6
            color: Theme.bg_shadow
            border.width: 3
            border.color: Theme.green
            clip: true

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    text: "HIT"
                    color: Theme.bright_green
                    font.family: Style.font_family
                    font.pixelSize: 10
                }

                Repeater {
                    model: hud.visible ? root.capped_items : []

                    DuckIcon {
                        id: hit_duck
                        required property var modelData
                        readonly property bool current: hit_duck.modelData.i === Screenshot.target_index
                        fill: hit_duck.current ? (hud_blink.on ? Theme.fg_strong : Theme.fg_muted) : Theme.fg_muted
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.cur_label
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: 10
                }
            }
        }

        Timer {
            id: hud_blink
            property bool on: true
            interval: 500
            repeat: true
            running: hud.visible
            onTriggered: hud_blink.on = !hud_blink.on
        }
    }

    Item {
        id: region_hud
        visible: root.region && root.mine && (Screenshot.phase === "select" || Screenshot.phase === "toolbar")
        x: root.width - width - 24
        y: root.height - height - 22
        width: region_score_col.implicitWidth + 16
        height: 40

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: Theme.bg_shadow
            border.width: 3
            border.color: Theme.green
        }

        Column {
            id: region_score_col
            anchors.centerIn: parent
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(root.tw) + "x" + Math.round(root.th)
                color: Theme.fg_strong
                font.family: Style.font_family
                font.pixelSize: 10
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "SCORE"
                color: Theme.bright_green
                font.family: Style.font_family
                font.pixelSize: 10
            }
        }
    }
}
