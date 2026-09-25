// home/quickshell/.config/quickshell/components/modern/CapsuleSlider.qml
import QtQuick
import QtQuick.Shapes
import Quickshell.Services.Pipewire
import "../../theme"
import ".." as Shared

// A level as a tall capsule on a recessed well: the node's live wave fills it up to the level, with a marker at the level and a red tip past 90%.
Item {
    id: root

    property real value: 0
    property bool muted: false
    property string glyph: ""
    property string label: ""
    property bool selected: false
    property bool interactive: true
    property bool show_readout: true
    // A solid gradient fill instead of the wave, for small capsules like the OSD's.
    property bool solid: false
    // A static glow rising toward the level instead of the wave, for levels without audio.
    property bool glow: false
    // Read-only sparkline: recent values (0-1, oldest first) as an area chart ending at the right edge.
    property var spark: []
    readonly property bool sparkline: root.spark.length > 0
    // Replaces the percent readout, e.g. a temperature.
    property string readout_text: ""
    // Live wave from this node; the monitor and the wave only run while peaks_on.
    property var node: null
    property bool peaks_on: false

    signal moved(real value)
    signal mute_clicked

    readonly property real level: Math.max(0, Math.min(1, root.value))
    readonly property real fill_width: root.width * root.level
    readonly property real radius: root.shaped ? 0 : height / 2
    // Oasis: slanted ends at the bar islands' angle instead of round ones, sand at the level.
    readonly property bool slanted: Style.level_layout === "slant"
    readonly property real slant: root.slanted ? root.height / 2 : 0
    // Metroid: a visor-glass bar with cut bottom corners, like its frames, and energy-tank ticks.
    readonly property bool visor: Style.level_layout === "visor"
    readonly property real cut: root.visor ? Math.round(root.height * 0.32) : 0
    readonly property bool shaped: root.slanted || root.visor
    readonly property real end_inset: root.slanted ? root.slant : root.visor ? root.cut : root.radius * 0.5
    readonly property color marker_color: root.shaped ? Theme.theme_secondary : Theme.theme_primary

    function outline() {
        const w = root.width, h = root.height, s = root.slant, c = root.cut;
        if (root.visor) return [Qt.point(0, 0), Qt.point(w, 0), Qt.point(w, h - c), Qt.point(w - c, h), Qt.point(c, h), Qt.point(0, h - c), Qt.point(0, 0)];
        return [Qt.point(0, 0), Qt.point(w, 0), Qt.point(w - s, h), Qt.point(s, h), Qt.point(0, 0)];
    }

    // The level wash's outline, from the left end up to the level.
    function wash() {
        const w = root.width, h = root.height, s = root.slant, c = root.cut;
        if (root.visor) {
            const f = Math.max(c, root.fill_width), yb = f > w - c ? h - (f - (w - c)) : h;
            return [Qt.point(0, 0), Qt.point(f, 0), Qt.point(f, yb), Qt.point(Math.min(f, w - c), h), Qt.point(c, h), Qt.point(0, h - c), Qt.point(0, 0)];
        }
        const f = Math.max(s, root.fill_width), d = s * 0.3;
        return [Qt.point(0, 0), Qt.point(f + d, 0), Qt.point(f - d, h), Qt.point(s, h), Qt.point(0, 0)];
    }
    readonly property real pad: Math.round(height * 0.42)

    implicitHeight: Style.px(34)

    // Peaks on a 60 dB scale so quiet audio still moves the wave.
    function db_level(p) {
        return p > 0 ? Math.max(0, 1 + Math.log(p) / Math.LN10 * 20 / 60) : 0;
    }

    // Recent peaks, newest last; the wave samples them once per frame.
    property var history: []
    function sample(n) {
        const h = root.history.length >= n ? root.history.slice(root.history.length - n + 1) : root.history.slice();
        h.push(root.db_level(peak_monitor.peak));
        root.history = h;
        return h.length >= n ? h : new Array(n - h.length).fill(0).concat(h);
    }
    onPeaks_onChanged: if (!root.peaks_on) root.history = []

    PwNodePeakMonitor {
        id: peak_monitor
        node: root.peaks_on ? root.node : null
        enabled: root.peaks_on
    }

    Rectangle {
        visible: !root.shaped
        anchors.fill: parent
        radius: root.radius
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.darker(Style.tab_well, 1.25) }
            GradientStop { position: 1; color: Style.tab_well }
        }
        border.width: root.selected ? 1.5 : 1
        border.color: root.selected ? Theme.theme_primary : Style.frame_border_color
    }

    // Shaped well and level wash: slanted like the bar islands, or visor glass with cut corners.
    Shape {
        visible: root.shaped
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.selected ? 1.5 : 1
            strokeColor: root.selected ? (root.visor ? Theme.theme_primary : Theme.theme_secondary) : Style.frame_border_color
            fillGradient: LinearGradient {
                y2: root.height
                GradientStop { position: 0; color: root.visor ? Qt.alpha(Theme.ui_visual_bg, 0.55) : Qt.darker(Style.tab_well, 1.25) }
                GradientStop { position: 1; color: root.visor ? Theme.bg_crust : Style.tab_well }
            }
            PathPolyline { path: root.outline() }
        }

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x2: Math.max(1, root.fill_width)
                GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary, 0.04) }
                GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary, root.glow ? 0.3 : 0.16) }
            }
            PathPolyline { path: root.wash() }
        }
    }

    // Energy-tank squares along the visor's foot, every tenth.
    Repeater {
        model: root.visor ? 9 : 0

        Rectangle {
            required property int index
            x: Math.round(root.width * (index + 1) / 10) - 1
            y: root.height - 5
            width: 3
            height: 3
            color: Qt.alpha(Theme.theme_primary, index === 4 ? 0.7 : 0.35)
        }
    }

    Rectangle {
        id: solid_fill
        visible: root.solid && root.fill_width > 0.5
        width: root.fill_width
        height: root.height
        radius: root.radius
        opacity: root.muted ? 0.4 : 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Style.selection_shade.a > 0 ? Style.selection_shade : Style.selection_bg }
            GradientStop { position: Math.min(1, root.width * 0.9 / Math.max(1, solid_fill.width)); color: Style.selection_bg }
            GradientStop { position: 1; color: root.level > 0.9 ? Theme.theme_label : Style.selection_bg }
        }
    }

    // The level region: a faint primary wash, the wave, and a red wash on the part past 90%.
    Item {
        id: wave_region
        visible: !root.solid && !root.sparkline
        x: root.end_inset
        width: Math.max(0, root.fill_width - x)
        height: root.height
        clip: true
        opacity: root.muted ? 0.4 : 1

        Rectangle {
            visible: !root.shaped
            x: -wave_region.x
            width: root.fill_width
            height: parent.height
            radius: root.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary, 0.04) }
                GradientStop { position: root.glow ? 0.7 : 1; color: Qt.alpha(Theme.theme_primary, root.glow ? 0.2 : 0.14) }
                GradientStop { position: 1; color: root.glow ? Qt.alpha(Theme.theme_primary_light, 0.42) : Qt.alpha(Theme.theme_primary, 0.14) }
            }
        }

        // A soft light band along the middle, brightest at the level.
        Rectangle {
            visible: root.glow
            x: -wave_region.x
            y: root.height * 0.3
            width: root.fill_width
            height: root.height * 0.4
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary_light, 0) }
                GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary_light, 0.28) }
            }
        }

        Shared.Waveform {
            visible: !root.glow
            y: root.height * 0.12
            width: parent.width
            height: root.height * 0.76
            sample: n => root.sample(n)
            gain: 1
            tint: root.visor ? Theme.info : Theme.theme_primary_light
            running: root.peaks_on && !root.solid && !root.glow
        }

        Rectangle {
            visible: root.level > 0.9
            x: root.width * 0.9 - wave_region.x
            width: Math.max(0, wave_region.width - x)
            height: parent.height
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.alpha(Theme.theme_label, 0) }
                GradientStop { position: 1; color: Qt.alpha(Theme.theme_label, 0.35) }
            }
        }
    }

    Shape {
        id: spark_shape
        visible: root.sparkline
        readonly property real x0: root.radius * 0.6
        readonly property real w: root.width - x0 * 2
        readonly property real chart_top: root.height * 0.14
        readonly property real h: root.height - chart_top * 2
        readonly property var line: {
            const n = root.spark.length;
            const pts = [];
            for (let i = 0; i < n; i++) {
                const v = Math.max(0, Math.min(1, root.spark[i]));
                pts.push(Qt.point(x0 + (n <= 1 ? w : i / (n - 1) * w), chart_top + h * (1 - v)));
            }
            if (n === 1) pts.unshift(Qt.point(x0, pts[0].y));
            return pts;
        }
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                y1: spark_shape.chart_top
                y2: spark_shape.chart_top + spark_shape.h
                GradientStop { position: 0; color: Qt.alpha(Theme.theme_label, 0.5) }
                GradientStop { position: 0.099; color: Qt.alpha(Theme.theme_label, 0.4) }
                GradientStop { position: 0.1; color: Qt.alpha(Theme.theme_primary_light, 0.38) }
                GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary, 0.04) }
            }
            PathPolyline {
                path: spark_shape.line.length ? [Qt.point(spark_shape.line[0].x, spark_shape.chart_top + spark_shape.h)].concat(spark_shape.line, [Qt.point(spark_shape.line[spark_shape.line.length - 1].x, spark_shape.chart_top + spark_shape.h)]) : []
            }
        }

        ShapePath {
            strokeColor: Qt.alpha(Theme.theme_primary_light, 0.8)
            strokeWidth: 1.4
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathPolyline { path: spark_shape.line }
        }
    }

    Shape {
        visible: root.shaped && !root.solid && !root.sparkline && root.level > 0
        anchors.fill: parent
        opacity: root.muted ? 0.4 : 1
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: marker_path
            readonly property real f: Math.max(root.end_inset, Math.min(root.width - root.end_inset, root.fill_width))
            strokeColor: root.level > 0.9 ? Theme.theme_label : root.marker_color
            strokeWidth: 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            startX: f + root.slant * 0.18
            startY: root.height * 0.2
            PathLine { x: marker_path.f - root.slant * 0.18; y: root.height * 0.8 }
        }
    }

    Rectangle {
        visible: !root.shaped && !root.solid && !root.sparkline && root.level > 0
        x: Math.max(root.radius * 0.5, Math.min(root.width - root.radius * 0.5, root.fill_width)) - 1
        y: root.height * 0.2
        width: 2
        height: root.height * 0.6
        radius: 1
        color: root.level > 0.9 ? Theme.theme_label : Theme.theme_primary
        opacity: root.muted ? 0.4 : 1
    }

    Text {
        id: icon_text
        x: root.pad
        anchors.verticalCenter: parent.verticalCenter
        text: root.glyph
        color: Style.text_fg
        style: Text.Outline
        styleColor: Qt.alpha(Style.tab_well, 0.9)
        font.family: Theme.font_family
        font.pixelSize: Style.fs(1)
    }

    Text {
        anchors.left: icon_text.right
        anchors.leftMargin: 8
        anchors.right: readout.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: root.label
        color: Style.text_fg
        style: Text.Outline
        styleColor: Qt.alpha(Style.tab_well, 0.9)
        font.family: Style.font_family
        font.pixelSize: Style.fs(-1)
        font.weight: Font.Medium
    }

    Text {
        id: readout
        visible: root.show_readout
        anchors.right: parent.right
        anchors.rightMargin: root.pad
        anchors.verticalCenter: parent.verticalCenter
        text: root.readout_text !== "" ? root.readout_text : root.muted ? "Muted" : Math.round(root.level * 100) + "%"
        color: Style.text_dim
        style: Text.Outline
        styleColor: Qt.alpha(Style.tab_well, 0.9)
        font.family: Style.number_font
        font.pixelSize: Style.fs(-2)
        font.features: { "tnum": 1 }
    }

    MouseArea {
        enabled: root.interactive
        anchors.fill: parent
        onPressed: mouse => root.moved(Math.max(0, Math.min(1, mouse.x / Math.max(1, root.width))))
        onPositionChanged: mouse => {
            if (pressed) root.moved(Math.max(0, Math.min(1, mouse.x / Math.max(1, root.width))));
        }
    }

    // The icon mutes, like the shared row's mute glyph.
    MouseArea {
        enabled: root.interactive && root.glyph !== ""
        width: root.pad * 2 + Style.font_size
        height: root.height
        onClicked: root.mute_clicked()
    }
}
