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

    readonly property bool drawing: root.visible && root.width > 0
    readonly property var top_points: {
        const src = CavaState.line_levels;
        if (!root.line || !root.drawing) return [];
        const n = src.length;
        const pts = [];
        for (let i = 0; i < n; i++) pts.push(Qt.point((n <= 1 ? 0 : i / (n - 1)) * root.width, root.height - 0.5 - src[i] * (root.height - 1)));
        return pts;
    }
    readonly property var fill_points: root.top_points.length ? root.top_points.concat([Qt.point(root.width, root.height), Qt.point(0, root.height)]) : []

    height: root.line ? 10 : 6
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

    Canvas {
        id: bars
        visible: !root.line
        anchors.fill: parent

        onPaint: {
            const ctx = bars.getContext("2d");
            ctx.reset();
            const levels = CavaState.levels;
            const n = root.bar_count;
            const w = bars.width / n;
            ctx.fillStyle = Theme.theme_primary;
            for (let i = 0; i < n; i++) {
                const level = levels[i] || 0;
                const h = 1 + level * (bars.height - 1);
                ctx.globalAlpha = 0.5 + 0.5 * level;
                const x0 = Math.round(i * w);
                ctx.fillRect(x0, bars.height - h, Math.round((i + 1) * w) - x0, h);
            }
        }

        onWidthChanged: bars.request()
        onHeightChanged: bars.request()
        onVisibleChanged: bars.request()

        function request() {
            if (bars.visible && bars.width > 0) bars.requestPaint();
        }

        Connections {
            target: CavaState
            function onLevelsChanged() { bars.request(); }
        }

        Connections {
            target: Theme
            function onTheme_primaryChanged() { bars.request(); }
        }
    }
}
