import QtQuick
import QtQuick.Shapes
import qs.core
import qs.theme
import qs.features.media
import "../../ui/CavaMath.js" as CavaMath

// The "wave" cava look: a low wave along the bar band's open edge, behind the islands. Bar-local, so the frame's
// corners do not touch it.
Item {
    id: root

    // Under a bottom bar the open edge is the top one, and the wave hangs from it.
    property bool flipped: false
    readonly property int amp: 18
    readonly property bool watching: MediaState.playing && PowerSource.on_ac
    readonly property bool shown: root.watching && !CavaState.silent_folded
    readonly property var wave: root.visible ? CavaMath.wave_points(CavaState.line_levels, root.width, root.height, root.amp, root.flipped) : null
    readonly property var line_path: root.wave ? root.wave.line.map(p => Qt.point(p[0], p[1])) : []
    readonly property var fill_path: root.wave ? root.wave.fill.map(p => Qt.point(p[0], p[1])) : []

    opacity: root.shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
    }

    // A folded wave still counts: cava must keep running to hear sound return.
    onWatchingChanged: CavaState.frame_viewers += root.watching ? 1 : -1
    Component.onCompleted: if (root.watching) CavaState.frame_viewers += 1
    Component.onDestruction: if (root.watching) CavaState.frame_viewers -= 1

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: Qt.alpha(Theme.theme_primary, 0.3)
            PathPolyline { path: root.fill_path }
        }

        ShapePath {
            strokeColor: Qt.alpha(Theme.theme_primary, 0.9)
            strokeWidth: 2
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.line_path }
        }
    }
}
