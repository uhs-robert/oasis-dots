import QtQuick
import QtQuick.Shapes
import qs.theme

// Recent mic levels, newest on the right, as a mirrored line wave.
Item {
    id: root

    // Calls sample only while true.
    property bool running: false
    // Holds the last recording while voxtype transcribes: yellow, gently wobbling, over a breathing glow.
    property bool frozen: false
    // Where the levels come from (n buckets, each 0..1) and their gain, supplied by the host so this widget stays out of features/voice.
    required property var sample
    required property real gain
    property color tint: "transparent"

    // After voxtype's own renderer: bucket averages that rise fast and fall slowly.
    readonly property int wave_count: 96
    property var wave_levels: []
    property real phase: 0
    property double last_tick: 0

    implicitWidth: 148
    implicitHeight: Style.px(18)

    function approach(current, target, stiffness, dt) {
        return current + (target - current) * (1 - Math.exp(-stiffness * dt));
    }

    function tick() {
        const now = Date.now();
        const dt = root.last_tick > 0 ? Math.min(0.05, Math.max(0.001, (now - root.last_tick) / 1000)) : 0.033;
        root.last_tick = now;
        const targets = root.sample(root.wave_count);
        const next = root.wave_levels.length === root.wave_count ? root.wave_levels.slice() : new Array(root.wave_count).fill(0);
        for (let i = 0; i < root.wave_count; i++) next[i] = root.approach(next[i], targets[i], targets[i] > next[i] ? 30 : 14, dt);
        root.wave_levels = next;
        root.phase += dt;
    }

    Timer {
        interval: 33
        repeat: true
        running: root.running
        triggeredOnStart: true
        onTriggered: root.tick()
        onRunningChanged: if (!running) {
            root.last_tick = 0;
            root.wave_levels = [];
        }
    }

    readonly property int columns_drawn: Math.max(24, Math.min(96, Math.floor(root.width / 5)))
    // Per-column envelope: interpolated from the smoothed levels, 3-tap neighbour smoothing, then gain.
    readonly property var envelope: {
        const n = root.columns_drawn;
        const src = root.wave_levels;
        const raw = new Array(n).fill(0);
        if (src.length > 0) {
            for (let i = 0; i < n; i++) {
                const f = (n <= 1 ? 0 : i / (n - 1)) * (src.length - 1);
                const lo = Math.floor(f);
                const hi = Math.min(src.length - 1, lo + 1);
                raw[i] = src[lo] * (1 - (f - lo)) + src[hi] * (f - lo);
            }
        }
        const out = new Array(n);
        for (let i = 0; i < n; i++) {
            const s = raw[Math.max(0, i - 1)] * 0.25 + raw[i] * 0.5 + raw[Math.min(n - 1, i + 1)] * 0.25;
            out[i] = Math.max(0.015, Math.min(1, s * root.gain));
        }
        return out;
    }
    readonly property bool hot_now: root.envelope.length > 0 && root.envelope[root.envelope.length - 1] >= 0.9
    readonly property color line_color: root.tint.a > 0 ? root.tint : root.frozen ? Style.pal.warning : root.hot_now ? Style.meter_hot : Style.meter_on
    readonly property real breath: 0.5 + 0.5 * Math.sin(root.phase * 1.6)
    readonly property real amp: root.height * 0.45
    readonly property var top_points: {
        const n = root.envelope.length;
        const pts = [];
        for (let i = 0; i < n; i++) pts.push(Qt.point((n <= 1 ? 0 : i / (n - 1)) * root.width, root.height / 2 - root.envelope[i] * root.amp));
        return pts;
    }
    readonly property var fill_points: {
        const n = root.envelope.length;
        const pts = [];
        for (let i = 0; i < n; i++) {
            const t = n <= 1 ? 0 : i / (n - 1);
            pts.push(Qt.point(t * root.width, root.height / 2 - (root.envelope[i] + Math.sin(root.phase * 2 + t * Math.PI * 3) * 0.04) * root.amp));
        }
        for (let i = n - 1; i >= 0; i--) {
            const t = n <= 1 ? 0 : i / (n - 1);
            pts.push(Qt.point(t * root.width, root.height / 2 + (root.envelope[i] - Math.sin(root.phase * 2 + t * Math.PI * 3) * 0.04) * root.amp));
        }
        return pts;
    }

    Rectangle {
        visible: root.frozen
        anchors.fill: parent
        anchors.margins: -(2 + root.breath * 5)
        radius: Style.radius(12)
        color: Qt.alpha(Style.pal.warning, 0.06 + root.breath * 0.08)
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: Qt.alpha(root.line_color, 0.18)
            PathPolyline { path: root.fill_points }
        }

        ShapePath {
            strokeColor: Qt.alpha(root.line_color, 0.19)
            strokeWidth: 5.6
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.top_points }
        }

        ShapePath {
            strokeColor: Qt.alpha(root.line_color, 0.41)
            strokeWidth: 2.8
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.top_points }
        }

        ShapePath {
            strokeColor: Qt.alpha(root.line_color, 0.75)
            strokeWidth: 1.4
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.top_points }
        }
    }
}
