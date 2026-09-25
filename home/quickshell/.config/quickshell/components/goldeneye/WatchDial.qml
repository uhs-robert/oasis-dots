// home/quickshell/.config/quickshell/components/goldeneye/WatchDial.qml
import QtQuick
import QtQuick.Shapes
import Quickshell.Hyprland
import "../../theme"
import ".."

// Bond's pause-menu watch face: a tick per workspace on a shallow arc, apps under their ticks, the laser hand on the focused one.
Item {
    id: root

    // The Workspaces module, for its icon, name and window helpers.
    required property Item host
    property var workspaces: []
    property bool compact: false

    readonly property int glyph: compact ? 13 : 15
    readonly property int lead: 6
    readonly property int face_top: 3
    readonly property int icon_drop: compact ? 7 : 8
    readonly property real max_sag: 6
    readonly property color lcd: Theme.theme_primary_light
    readonly property color lcd_low: Qt.tint(Theme.theme_primary_light, Qt.alpha(Theme.theme_primary, 0.3))
    readonly property color ink: Theme.bg_core
    readonly property color laser: Theme.theme_label
    readonly property color bezel: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.fg_muted, 0.2))
    readonly property color metal:Qt.tint(Theme.bg_surface, Qt.alpha(Theme.fg_muted, 0.4))

    function gap(on) {
        return on ? 6 : 2;
    }

    function slot_width(k, on) {
        return k ? k * root.glyph + (k - 1) * root.gap(on) + 10 : 14;
    }

    readonly property var slots: {
        const out = [];
        let x = root.lead;
        for (const w of root.workspaces) {
            const k = w.toplevels.values.length, wd = root.slot_width(k, w.focused);
            out.push({ id: w.id, x: x, mid: x + wd / 2, w: wd, k: k, focused: w.focused, active: w.active });
            x += wd;
        }
        return out;
    }
    readonly property real track: slots.length ? slots[slots.length - 1].x + slots[slots.length - 1].w : lead
    readonly property var target: {
        let hit = null;
        for (const s of root.slots) {
            if (s.focused) return s;
            if (s.active && !hit) hit = s;
        }
        return hit;
    }

    implicitWidth: Math.ceil(track + 8 + ghost.implicitWidth + 7)
    implicitHeight: 34
    clip: true

    // A circle wide enough that the arc sags at most max_sag px end to end.
    readonly property real radius_px: Math.max(width * 4, width * width / (8 * max_sag), 1)
    readonly property real cx: width / 2
    readonly property real cy: face_top + radius_px

    function arc_y(x) {
        const dx = x - root.cx;
        return root.cy - Math.sqrt(root.radius_px * root.radius_px - dx * dx);
    }

    // A radial segment at x, d0..d1 px in from the arc toward the centre.
    function seg(x, d0, d1) {
        const y = root.arc_y(x), r = root.radius_px;
        const ux = (root.cx - x) / r, uy = (root.cy - y) / r;
        return "M" + (x + ux * d0).toFixed(2) + " " + (y + uy * d0).toFixed(2) + "L" + (x + ux * d1).toFixed(2) + " " + (y + uy * d1).toFixed(2);
    }

    readonly property string arc_path: "M0 " + arc_y(0).toFixed(2) + "A" + radius_px + " " + radius_px + " 0 0 1 " + width + " " + arc_y(width).toFixed(2)
    readonly property string face_path: {
        const w = root.width, h = root.height, c = 8;
        return root.arc_path + "V" + (h - c) + "Q" + w + " " + h + " " + (w - c) + " " + h + "H" + c + "Q0 " + h + " 0 " + (h - c) + "Z";
    }

    property real hand_x: target ? target.mid : -1
    Behavior on hand_x {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
    readonly property string hand_path: {
        if (root.hand_x < 0) return "";
        const y = root.arc_y(root.hand_x);
        return root.seg(root.hand_x, -1, (root.height + 4 - y) * root.radius_px / (root.cy - y));
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: root.face_top
                x2: 0
                y2: root.height
                GradientStop { position: 0; color: root.lcd }
                GradientStop { position: 1; color: root.lcd_low }
            }
            PathSvg { path: root.face_path }
        }

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: root.face_top + root.max_sag
                GradientStop { position: 0; color: root.bezel }
                GradientStop { position: 1; color: Theme.bg_crust }
            }
            PathSvg { path: root.arc_path + "V0H0Z" }
        }

        ShapePath {
            strokeWidth: 2.5
            strokeColor: root.metal
            fillColor: "transparent"
            PathSvg { path: root.arc_path }
        }

        ShapePath {
            strokeWidth: 0.8
            strokeColor: Qt.alpha(root.ink, 0.3)
            fillColor: "transparent"
            PathSvg { path: "M0 " + (root.arc_y(0) + 1.6).toFixed(2) + "A" + root.radius_px + " " + root.radius_px + " 0 0 1 " + root.width + " " + (root.arc_y(root.width) + 1.6).toFixed(2) }
        }

        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(root.ink, 0.35)
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathSvg {
                path: {
                    let d = "";
                    for (let m = 6; m < root.width - 4; m += 5) d += root.seg(m, 0, 2);
                    return d || "M0 0";
                }
            }
        }

        ShapePath {
            strokeWidth: 4
            strokeColor: root.hand_path === "" ? "transparent" : Qt.alpha(root.laser, root.target && root.target.focused ? 0.3 : 0.14)
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathSvg { path: root.hand_path || "M0 0" }
        }

        ShapePath {
            strokeWidth: 1.3
            strokeColor: root.hand_path === "" ? "transparent" : Qt.alpha(root.laser, root.target && root.target.focused ? 1 : 0.5)
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathSvg { path: root.hand_path || "M0 0" }
        }

        ShapePath {
            strokeWidth: 2
            strokeColor: root.ink
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathSvg { path: root.slots.filter(s => s.k && !s.focused).map(s => root.seg(s.mid, 0, 5)).join("") || "M0 0" }
        }

        ShapePath {
            strokeWidth: 1.3
            strokeColor: root.ink
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathSvg { path: root.slots.filter(s => !s.k && !s.focused).map(s => root.seg(s.mid, 0, 3.5)).join("") || "M0 0" }
        }

        ShapePath {
            strokeWidth: 2
            strokeColor: root.laser
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathSvg { path: root.slots.filter(s => s.focused).map(s => root.seg(s.mid, 0, 8)).join("") || "M0 0" }
        }
    }

    Repeater {
        model: Math.ceil(root.height / 3)

        Rectangle {
            required property int index
            y: index * 3
            width: root.width
            height: 1
            color: Qt.alpha(Theme.bg_crust, 0.06)
        }
    }

    Text {
        id: ghost
        anchors.right: parent.right
        anchors.rightMargin: 7
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        text: "8".repeat(Math.max(2, readout.text.length))
        color: Qt.alpha(root.ink, 0.08)
        font: readout.font
    }

    Text {
        id: readout
        anchors.right: ghost.right
        anchors.bottom: ghost.bottom
        text: root.target ? String(root.target.id) : "--"
        color: Qt.alpha(root.ink, root.target && root.target.focused ? 1 : 0.55)
        font.family: Style.number_font
        font.bold: true
        font.pixelSize: Style.bar_font_size + 2
    }

    Repeater {
        model: root.workspaces

        Item {
            id: slot
            required property var modelData
            required property int index
            readonly property var info: root.slots[index] || { x: 0, mid: 0, w: 0 }
            readonly property real arc_at: root.arc_y(info.mid)

            x: info.x
            width: info.w
            height: root.height

            MouseArea {
                anchors.fill: parent
                onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = '" + slot.modelData.id + "' })")
            }

            HoverHandler {
                id: slot_hover
            }

            Rectangle {
                y: slot.arc_at + 2
                width: parent.width
                height: parent.height - y
                color: root.ink
                opacity: !slot.modelData.active && slot_hover.hovered ? 0.08 : 0

                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(slot.arc_at + root.icon_drop)
                spacing: root.gap(slot.modelData.focused)

                Repeater {
                    model: slot.modelData.toplevels.values

                    WorkspaceIcon {
                        host: root.host
                        workspace_id: slot.modelData.id
                        glyph: root.glyph
                    }
                }
            }
        }
    }
}
