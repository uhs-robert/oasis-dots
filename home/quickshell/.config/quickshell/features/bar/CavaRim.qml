import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.theme
import qs.features.media
import "../../ui/CavaMath.js" as CavaMath
import "../../ui/frames/FrameGeometry.js" as Frame

// The "rim" cava look: the line round the screen frame's hole brightens and thickens with the bass, above the frame.
// One click-through full-screen window drawn in the canonical frame, as ScreenFrame is, so the rim follows every
// corner (Frame.frame_stroke) without corner code of its own.
Scope {
    id: root

    required property ShellScreen screen
    required property var layout
    readonly property bool watching: MediaState.playing && PowerSource.on_ac
    readonly property bool shown: root.watching && !CavaState.silent_folded && CavaState.bass >= CavaMath.SILENT
    readonly property real bass: CavaState.bass
    readonly property real width_px: CavaMath.rim_width(root.bass)
    readonly property color rim_color: Qt.alpha(Qt.lighter(Theme.theme_primary, 1 + root.bass * 0.8), CavaMath.rim_alpha(root.bass))
    property real fade: root.shown ? 1 : 0

    Behavior on fade {
        NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
    }

    // A silent or folded rim draws nothing but still counts: cava must keep running to hear sound return.
    onWatchingChanged: CavaState.frame_viewers += root.watching ? 1 : -1
    Component.onCompleted: if (root.watching) CavaState.frame_viewers += 1
    Component.onDestruction: if (root.watching) CavaState.frame_viewers -= 1

    PanelWindow {
        screen: root.screen
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        visible: root.fade > 0
        WlrLayershell.namespace: "quickshell-cava-rim"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Item {
            width: root.layout.length
            height: root.layout.depth
            opacity: root.fade
            transform: Matrix4x4 {
                matrix: {
                    const m = Frame.to_screen(root.layout);
                    return Qt.matrix4x4(m[0], m[2], 0, m[4], m[1], m[3], 0, m[5], 0, 0, 1, 0, 0, 0, 0, 1);
                }
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: root.width_px
                    strokeColor: root.rim_color
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    joinStyle: ShapePath.MiterJoin
                    PathPolyline { path: Frame.frame_stroke(root.layout, root.width_px / 2).map(p => Qt.point(p[0], p[1])) }
                }
            }

            // The straight stretch of the near edge, under the bar strip, which frame_stroke leaves to the strip's own rim.
            Rectangle {
                visible: root.layout.has_bar
                x: root.layout.straight[0]
                width: root.layout.straight[1] - root.layout.straight[0]
                height: root.width_px
                y: root.layout.near - root.width_px
                color: root.rim_color
            }
        }
    }
}
