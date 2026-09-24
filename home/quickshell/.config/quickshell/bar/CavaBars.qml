// home/quickshell/.config/quickshell/bar/CavaBars.qml
import QtQuick
import QtQuick.Shapes
import "../theme"
import "../services"

// Cava drawn inside an island's bottom edge, as bars or a smoothed line, on the island's own color.
Item {
    id: root

    property bool active: MediaState.playing
    readonly property int bar_count: CavaState.bar_count
    readonly property bool line: Style.cava_line

    // Line mode, like the voxtype wave: levels rise fast and fall slowly, then blend with neighbours.
    property var smoothed: []
    property double last_ms: 0
    readonly property var line_levels: {
        const src = root.smoothed;
        const n = src.length;
        const out = new Array(n);
        for (let i = 0; i < n; i++) out[i] = src[Math.max(0, i - 1)] * 0.25 + src[i] * 0.5 + src[Math.min(n - 1, i + 1)] * 0.25;
        return out;
    }
    readonly property var top_points: {
        const n = root.line_levels.length;
        const pts = [];
        for (let i = 0; i < n; i++) pts.push(Qt.point((n <= 1 ? 0 : i / (n - 1)) * root.width, root.height - 0.5 - root.line_levels[i] * (root.height - 1)));
        return pts;
    }
    readonly property var fill_points: root.top_points.concat([Qt.point(root.width, root.height), Qt.point(0, root.height)])

    Connections {
        target: CavaState
        enabled: root.line && root.visible
        function onLevelsChanged() {
            const now = Date.now();
            const dt = root.last_ms > 0 ? Math.min(0.05, Math.max(0.001, (now - root.last_ms) / 1000)) : 0.016;
            root.last_ms = now;
            const target = CavaState.levels;
            const next = root.smoothed.length === target.length ? root.smoothed.slice() : new Array(target.length).fill(0);
            for (let i = 0; i < target.length; i++) {
                const k = target[i] > next[i] ? 30 : 14;
                next[i] = next[i] + (target[i] - next[i]) * (1 - Math.exp(-k * dt));
            }
            root.smoothed = next;
        }
    }

    height: 6
    opacity: root.active ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
    }

    Shape {
        visible: root.line
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: Qt.alpha(Theme.theme_primary, 0.18)
            PathPolyline { path: root.fill_points }
        }

        ShapePath {
            strokeColor: Qt.alpha(Theme.theme_primary, 0.3)
            strokeWidth: 3
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathPolyline { path: root.top_points }
        }

        ShapePath {
            strokeColor: Qt.alpha(Theme.theme_primary, 0.85)
            strokeWidth: 1.2
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathPolyline { path: root.top_points }
        }
    }

    Row {
        visible: !root.line
        anchors.fill: parent

        Repeater {
            model: root.bar_count

            Rectangle {
                required property int index
                readonly property real level: CavaState.levels[index] || 0

                anchors.bottom: parent.bottom
                width: root.width / root.bar_count
                height: 1 + level * (root.height - 1)
                color: Theme.theme_primary
                opacity: 0.5 + 0.5 * level
            }
        }
    }
}
