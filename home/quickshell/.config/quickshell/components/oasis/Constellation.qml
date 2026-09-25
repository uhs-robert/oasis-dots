// home/quickshell/.config/quickshell/components/oasis/Constellation.qml
import QtQuick
import QtQuick.Shapes
import Quickshell.Hyprland
import "../../theme"
import ".."

// Workspaces as a constellation: a star per workspace with its apps beside it, stars linked across the gaps; the focused one a sand sparkle.
Item {
    id: root

    // The Workspaces module, for its icon, name and window helpers.
    required property Item host
    property var workspaces: []
    property bool compact: false
    property int bar_height: 30

    readonly property int glyph: compact ? 15 : 17
    readonly property int gap: 4
    // Star centre from the slot's left edge, apps start after it, and the link runs in the gap after the apps.
    readonly property int star_x: 10
    readonly property int apps_x: 26
    readonly property int link_room: 16
    readonly property color sand: Theme.theme_secondary
    readonly property var lifts: [0, -3, 2, -2, 3]

    function slot_width(k) {
        return k > 0 ? root.apps_x + k * root.glyph + (k - 1) * root.gap + root.link_room : root.star_x * 2 + root.link_room - 4;
    }

    readonly property var slots: {
        const out = [];
        let x = 0;
        for (const w of root.workspaces) {
            const k = w.toplevels.values.length, wd = root.slot_width(k);
            const end = k > 0 ? x + root.apps_x + k * root.glyph + (k - 1) * root.gap : x + root.star_x;
            out.push({ id: w.id, x: x, w: wd, cx: x + root.star_x, cy: root.bar_height / 2 + root.lifts[Math.abs(w.id) % 5], end: end, k: k, focused: w.focused, active: w.active });
            x += wd;
        }
        return out;
    }

    // An empty last slot still needs room for its two-digit label right of the star.
    implicitWidth: {
        const s = slots.length ? slots[slots.length - 1] : null;
        return s ? Math.max(s.x + s.w - root.link_room + 4, s.cx + 5 + label_metrics.advanceWidth(String(s.id)) + 2) : 0;
    }
    implicitHeight: root.bar_height

    FontMetrics {
        id: label_metrics
        font.family: Style.bar_font_family
        font.pixelSize: 9
        font.weight: Font.DemiBold
    }

    // A four-point sparkle of radius r at (x, y).
    function sparkle(x, y, r) {
        const k = r * 0.18;
        const p = (px, py) => (x + px).toFixed(2) + " " + (y + py).toFixed(2);
        return "M" + p(0, -r) + "Q" + p(k, -k) + " " + p(r, 0) + "Q" + p(k, k) + " " + p(0, r) + "Q" + p(-k, k) + " " + p(-r, 0) + "Q" + p(-k, -k) + " " + p(0, -r) + "Z";
    }

    function circle(x, y, r) {
        return "M" + (x - r) + " " + y + "a" + r + " " + r + " 0 1 0 " + 2 * r + " 0a" + r + " " + r + " 0 1 0 " + -2 * r + " 0";
    }

    function star_radius(s) {
        return s.focused ? 9 : s.k ? 6.5 : 3;
    }

    function lit(s) {
        return s.k > 0 || s.focused;
    }

    // Solid links join two lit stars; any link touching an empty star is dashed. Each runs from a slot's last app to the next star.
    function links(solid) {
        let d = "";
        for (let i = 1; i < root.slots.length; i++) {
            const a = root.slots[i - 1], b = root.slots[i];
            if ((root.lit(a) && root.lit(b)) !== solid) continue;
            const x0 = a.k > 0 ? a.end + 4 : a.cx + root.star_radius(a) + 3, x1 = b.cx - root.star_radius(b) - 3;
            if (x1 - x0 > 2) d += "M" + x0.toFixed(2) + " " + a.cy.toFixed(2) + "L" + x1.toFixed(2) + " " + b.cy.toFixed(2);
        }
        return d || "M0 0";
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(Theme.theme_primary, 0.55)
            fillColor: "transparent"
            PathSvg { path: root.links(true) }
        }

        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(Theme.theme_primary, 0.4)
            fillColor: "transparent"
            strokeStyle: ShapePath.DashLine
            dashPattern: [2, 3]
            PathSvg { path: root.links(false) }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: Qt.alpha(root.sand, 0.1)
            PathSvg { path: root.slots.filter(s => s.focused).map(s => root.circle(s.cx, s.cy, 10)).join("") || "M0 0" }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: Qt.alpha(root.sand, 0.18)
            PathSvg { path: root.slots.filter(s => s.focused).map(s => root.circle(s.cx, s.cy, 5.5)).join("") || "M0 0" }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: root.sand
            PathSvg { path: root.slots.filter(s => s.focused).map(s => root.sparkle(s.cx, s.cy, 9)).join("") || "M0 0" }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: Theme.fg_strong
            PathSvg { path: root.slots.filter(s => s.focused).map(s => root.circle(s.cx, s.cy, 1.4)).join("") || "M0 0" }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: Theme.theme_secondary_strong
            PathSvg { path: root.slots.filter(s => !s.focused && s.active && s.k).map(s => root.sparkle(s.cx, s.cy, 7.5)).join("") || "M0 0" }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: Theme.theme_primary_light
            PathSvg { path: root.slots.filter(s => !s.focused && !s.active && s.k).map(s => root.sparkle(s.cx, s.cy, 6.5)).join("") || "M0 0" }
        }

        ShapePath {
            strokeWidth: 1.2
            strokeColor: Theme.fg_dim
            fillColor: "transparent"
            PathSvg { path: root.slots.filter(s => !s.focused && !s.k).map(s => root.circle(s.cx, s.cy, 3)).join("") || "M0 0" }
        }
    }

    Repeater {
        model: root.workspaces

        Item {
            id: slot
            required property var modelData
            required property int index
            readonly property var info: root.slots[index] || { x: 0, w: 0, cx: 0, cy: 0, k: 0, focused: false }

            x: info.x
            width: info.w - (info.k > 0 ? root.link_room - 4 : 0)
            height: root.height

            MouseArea {
                anchors.fill: parent
                onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = '" + slot.modelData.id + "' })")
            }

            HoverHandler {
                id: slot_hover
            }

            Text {
                x: root.star_x + (slot.info.focused ? 5 : 4)
                y: slot.info.cy - implicitHeight - (slot.info.focused ? 3 : 2)
                text: String(slot.modelData.id)
                color: slot.info.focused ? root.sand : slot_hover.hovered ? Theme.fg_strong : slot.info.k ? Theme.fg_dim : Theme.fg_muted
                font.family: Style.bar_font_family
                font.pixelSize: 9
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }

            Row {
                x: root.apps_x
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.gap

                Repeater {
                    model: slot.modelData.toplevels.values

                    WorkspaceIcon {
                        host: root.host
                        workspace_id: slot.modelData.id
                        glyph: root.glyph
                        opacity: slot.info.focused || slot_hover.hovered ? 1 : 0.75
                    }
                }
            }
        }
    }
}
