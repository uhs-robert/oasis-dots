import QtQuick
import QtQuick.Shapes
import qs.theme
import qs.core
import qs.styles.goldeneye as GE
import "../Watch.js" as W

// The Settings body as a round watch, for the GoldenEye settings skin's `layout` part (features/settings/README.md).
// A bezel ring holds the four groups as flat arcs, the selected one lit. The selected group's sections sit on a 240 degree
// sweep over the top with a lit marker on the selected one. The real pane goes in the face centre, over hands that show the
// time and dim behind the rows. A one-line readout sits in the lower half. The full help (the real docked panel) opens over
// the face in landscape and sits under the case in portrait.
Item {
    id: root

    // Filled by SettingsPopup right after creation; the blank keeps the bindings quiet until then.
    property var ctx: ({ portrait: false, open: false, wide: false, time_text: d => "", groups: [], group_index: 0, section_index: 0, nav_index: 0, in_pane: false, help_shown: false, picking: false, description: "", select_section: i => {}, select_group: i => {}, enter: () => {} })

    readonly property var group: root.ctx.groups[root.ctx.group_index] || { name: "", sections: [], labels: [] }
    readonly property bool stacked_help: root.height > root.width
    readonly property real rad: Math.min(root.width, root.height) / 2 - 6
    // Every size below is a share of the case radius, so the watch scales whole.
    readonly property real u: root.rad / 525
    readonly property real cx: root.width / 2
    readonly property real cy: root.stacked_help ? root.rad + 6 : root.height / 2

    // The overlay: while a list is open, a section that needs room (`ctx.wide`) has the cursor, or (landscape) the full help
    // is open, the pane and panel take the whole body in Default's proportions under one opaque ground that hides the watch.
    // The pane stays visible, so keys never act on rows nobody sees.
    readonly property bool overlay: root.ctx.picking || (root.ctx.in_pane && root.ctx.wide) || (!root.stacked_help && root.ctx.help_shown)
    readonly property real gap: 12
    readonly property real overlay_width: root.ctx.help_shown && !root.ctx.picking && !root.ctx.wide ? Math.min(root.width, root.height * 1.5) : root.width
    readonly property rect ground_rect: Qt.rect((root.width - root.overlay_width) / 2 + root.gap, root.gap, root.overlay_width - 2 * root.gap, root.height - 2 * root.gap)

    // Where SettingsPopup puts the pane and the docked panel, in this item's coordinates.
    readonly property rect pane_rect: {
        const g = root.ground_rect, pad = 12;
        // A wide section keeps to its rows until Enter: its hero or strip starts below them and would show as a clipped box.
        if (!root.overlay) return Qt.rect(root.cx - root.rad * 0.40, root.cy - root.rad * 0.36, root.rad * 0.80, root.rad * (root.ctx.wide ? 0.46 : 0.66));
        if (root.stacked_help) return Qt.rect(g.x + pad, g.y + pad, g.width - 2 * pad, g.height * 0.62);
        return Qt.rect(g.x + pad, g.y + pad, g.width * 0.58 - pad, g.height - 2 * pad);
    }
    readonly property rect panel_rect: {
        const g = root.ground_rect, pad = 12;
        if (root.stacked_help) {
            if (root.overlay) return Qt.rect(g.x + pad, g.y + g.height * 0.62 + 2 * pad, g.width - 2 * pad, g.height * 0.38 - 3 * pad);
            return Qt.rect(24, root.cy + root.rad + 36, root.width - 48, Math.max(0, root.height - root.cy - root.rad - 48));
        }
        return Qt.rect(g.x + g.width * 0.6, g.y + pad, g.width * 0.4 - pad, g.height - 2 * pad);
    }
    readonly property bool panel_shown: root.stacked_help || root.overlay
    readonly property bool panel_stacked: root.stacked_help

    readonly property bool face_clear: !root.overlay
    readonly property color face_color: Qt.alpha(Style.wk.panel_bottom, 1)

    // Hands run only while Settings is open: this item is destroyed with the popup's skin, and the timer stops with the popup.
    // On battery the second hand hides and the time updates once a minute.
    property date now: new Date()
    Timer {
        interval: PowerSource.on_ac ? 1000 : 60000
        running: root.ctx.open && root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    // The case and its face.
    Rectangle {
        x: root.cx - root.rad; y: root.cy - root.rad; width: root.rad * 2; height: width; radius: width / 2
        color: Style.wk.frame
        border.width: 2; border.color: Style.wk.rim
    }
    Rectangle {
        x: root.cx - root.rad * 0.835; y: root.cy - root.rad * 0.835; width: root.rad * 1.67; height: width; radius: width / 2
        color: root.face_color
        border.width: 1; border.color: Style.wk.edge
    }

    // The group arcs on the bezel, on the diagonals so the bottom pair clears the readout.
    Item {
        x: root.cx; y: root.cy
        Repeater {
            model: root.ctx.groups
            Item {
                id: arc
                required property var modelData
                required property int index
                readonly property bool lit: index === root.ctx.group_index
                readonly property real at: 315 + index * 90 > 360 ? index * 90 - 45 : 315 + index * 90
                readonly property real r_mid: root.rad * 0.915
                readonly property bool low: at > 90 && at < 270
                readonly property string name: modelData.name.toUpperCase()

                Shape {
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: root.rad * 0.14
                        strokeColor: arc.lit ? Qt.alpha(Style.wk.soft, 0.55) : Qt.alpha(Style.wk.bar_off, 0.5)
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap
                        PathAngleArc { centerX: 0; centerY: 0; radiusX: arc.r_mid; radiusY: arc.r_mid; startAngle: arc.at - 90 - 40; sweepAngle: 80 }
                    }
                }
                Repeater {
                    model: arc.name.length
                    Item {
                        id: ch
                        required property int index
                        readonly property real step: Math.round(21 * root.u) * 1.1 / arc.r_mid * 180 / Math.PI
                        readonly property real off: (index - (arc.name.length - 1) / 2) * step
                        rotation: arc.low ? arc.at - off + 180 : arc.at + off
                        Text {
                            text: arc.name.charAt(ch.index)
                            x: -width / 2
                            y: arc.low ? arc.r_mid - height / 2 : -arc.r_mid - height / 2
                            color: arc.lit ? Style.wk.lit : Style.wk.soft
                            opacity: arc.lit ? 1 : 0.75
                            font.family: W.head_font
                            font.pixelSize: Math.round(21 * root.u)
                        }
                    }
                }
                MouseArea {
                    x: Math.sin(arc.at * Math.PI / 180) * arc.r_mid - width / 2
                    y: -Math.cos(arc.at * Math.PI / 180) * arc.r_mid - height / 2
                    width: root.rad * 0.42; height: width
                    onClicked: root.ctx.select_group(arc.index)
                }
            }
        }
    }

    // The section sweep: 240 degrees over the top, a tick for each section and a lit marker on the selected one.
    Item {
        x: root.cx; y: root.cy
        Repeater {
            model: root.group.sections.length
            Item {
                id: sec
                required property int index
                readonly property bool lit: index === root.ctx.section_index
                readonly property real ang: root.group.sections.length < 2 ? 0 : -120 + index * 240 / (root.group.sections.length - 1)
                rotation: ang
                Rectangle {
                    x: -(sec.lit ? 3 : 1.5) * root.u; y: -root.rad * 0.835
                    width: (sec.lit ? 6 : 3) * root.u; height: root.rad * (sec.lit ? 0.07 : 0.04)
                    color: sec.lit ? Style.wk.lit : Style.wk.dim
                }
                // The lit marker: a knob on the bezel, with a glow behind it.
                Rectangle {
                    visible: sec.lit
                    x: -13 * root.u; y: -root.rad * 0.91 - 13 * root.u; width: 26 * root.u; height: width; radius: width / 2
                    color: Style.wk.lit; opacity: 0.25
                }
                Rectangle {
                    visible: sec.lit
                    x: -7 * root.u; y: -root.rad * 0.91 - 7 * root.u; width: 14 * root.u; height: width; radius: width / 2
                    color: Style.wk.lit
                }
            }
        }
        Repeater {
            model: root.group.sections.length
            Text {
                id: lab
                required property int index
                readonly property real a: (root.group.sections.length < 2 ? 0 : -120 + index * 240 / (root.group.sections.length - 1)) * Math.PI / 180
                x: Math.sin(a) * root.rad * 0.70 - width / 2
                y: -Math.cos(a) * root.rad * 0.70 - height / 2
                text: root.group.labels[index] || ""
                color: index === root.ctx.section_index ? Style.wk.lit : Style.wk.soft
                font.family: W.mono_font
                font.pixelSize: Math.round(19 * root.u)
                font.bold: index === root.ctx.section_index
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: {
                        root.ctx.select_section(root.group.sections[lab.index]);
                        root.ctx.enter();
                    }
                }
            }
        }
    }

    // The live hands. The lock's WatchHands plate is scaled non-uniformly so its elliptical reach becomes a circle.
    GE.WatchHands {
        now: root.now
        show_seconds: PowerSource.on_ac
        x: root.cx - 510; y: root.cy - 360
        transform: Scale { origin.x: 510; origin.y: 360; xScale: root.rad * 0.66 / 322; yScale: root.rad * 0.66 / 242 }
    }
    Rectangle {
        x: root.cx - 7 * root.u; y: root.cy - 7 * root.u; width: 14 * root.u; height: width
        radius: width / 2
        color: Style.wk.frame; border.width: 2; border.color: Style.wk.dim
    }

    // The hands dim where they cross the rows: a face-coloured veil between them and the pane.
    Rectangle {
        visible: root.face_clear
        x: root.pane_rect.x - 8 * root.u; y: root.pane_rect.y - 34 * root.u
        width: root.pane_rect.width + 16 * root.u; height: root.pane_rect.height + 42 * root.u
        radius: 10 * root.u
        color: root.face_color; opacity: 0.82
    }

    Text {
        visible: root.face_clear
        x: root.cx - width / 2; y: root.pane_rect.y - 28 * root.u
        text: (root.group.name + "  /  " + (root.group.labels[root.ctx.section_index] || "")).toUpperCase()
        color: Style.wk.mid
        font.family: W.head_font; font.pixelSize: Math.round(14 * root.u)
    }

    // The one-line readout in the lower half, with the digital time at its right end.
    Rectangle {
        visible: root.face_clear
        x: root.cx - root.rad * 0.46; y: root.cy + root.rad * 0.43
        width: root.rad * 0.92; height: root.rad * 0.27; radius: 10 * root.u
        color: root.face_color; opacity: 0.8
    }
    Item {
        visible: root.face_clear
        width: root.rad * 0.92; height: 30 * root.u
        x: root.cx - width / 2; y: root.cy + root.rad * 0.46
        Rectangle { width: parent.width; height: 1; color: Style.wk.edge }
        Text {
            anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: 3 * root.u
            width: parent.width
            text: root.ctx.description.split("\n")[0]
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            color: Style.wk.mid
            font.family: W.mono_font; font.pixelSize: Math.round(16 * root.u)
        }
        Text {
            visible: !root.stacked_help
            anchors.top: parent.bottom; anchors.topMargin: 14 * root.u
            text: "? help"
            color: Style.wk.dim
            font.family: W.mono_font; font.pixelSize: Math.round(14 * root.u)
        }
        Text {
            anchors.top: parent.bottom; anchors.topMargin: 6 * root.u
            anchors.right: parent.right
            text: root.ctx.time_text(root.now)
            color: Style.wk.lit
            font.family: W.digit_font; font.pixelSize: Math.round(34 * root.u)
        }
    }

    // The ground under the panel: the overlay's body-sized sheet in landscape, a card under the case in portrait. Opaque and
    // input-blocking, so a click on it never reaches a section label or arc beneath.
    Rectangle {
        id: ground
        visible: root.overlay || root.stacked_help
        x: root.overlay ? root.ground_rect.x : 12
        y: root.overlay ? root.ground_rect.y : root.panel_rect.y - 12
        width: root.overlay ? root.ground_rect.width : root.width - 24
        height: root.overlay ? root.ground_rect.height : Math.max(0, root.height - y - 6)
        radius: 12
        color: root.face_color; border.width: 1; border.color: Style.wk.edge
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }
    }
}
