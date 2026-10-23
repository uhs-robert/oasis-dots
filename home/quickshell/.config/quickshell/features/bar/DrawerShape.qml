import QtQuick
import QtQuick.Shapes
import Quickshell.Hyprland
import qs.theme
import "DrawerGeometry.js" as Drawer

// A drawer's shape (DrawerGeometry.js) in the screen frame's material: the fill and the frame's rim and inset line
// round it, open on the attached side. It draws nothing outside its surface and nothing inside the body but the fill.
Item {
    id: root

    required property var layout
    property string screen_name: ""
    // The line is lit on the focused monitor only, switching with the frame's (ScreenFrame).
    readonly property bool focused: !!Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === root.screen_name
    // With translucent islands the fill takes their opacity and covers only the hole, so it never stacks on the frame's
    // own fill; the frame and the strip leave their lines out under the window (ScreenFrames.drawer_windows). Otherwise it
    // is opaque and the cover strip hides the lines.
    property bool translucent: false
    property color fill_color: root.translucent ? Style.island_fill(Style.strip_color) : Style.strip_color
    // How far from the attached edge the rim and inset line run, for a body that draws its own edge; negative for all.
    property real lines_depth: -1
    property int rim_width: Style.bar_border_width
    property color rim_color: Style.screen_frame_rim_color(root.focused)
    property real inset_gap: Style.bar_inset_gap
    property real inset_width: Style.bar_inset_width
    property color inset_color: Style.screen_frame_inset_color(root.focused)
    Behavior on rim_color {
        ColorAnimation { duration: 200 }
    }
    Behavior on inset_color {
        ColorAnimation { duration: 200 }
    }

    // For the caller's content and input region, in the surface's coordinates.
    readonly property rect body_rect: {
        const r = Drawer.body_rect(root.layout);
        return Qt.rect(r.x, r.y, r.width, r.height);
    }

    implicitWidth: root.layout.surface.width
    implicitHeight: root.layout.surface.height

    Item {
        width: root.layout.length
        height: root.layout.depth
        transform: Matrix4x4 {
            matrix: {
                const m = Drawer.drawer_affine(root.layout);
                return Qt.matrix4x4(m[0], m[2], 0, m[4], m[1], m[3], 0, m[5], 0, 0, 1, 0, 0, 0, 0, 1);
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: root.fill_color
                PathPolyline {
                    path: (root.translucent ? Drawer.hole_fill_loop(root.layout) : Drawer.fill_loop(root.layout)).map(p => Qt.point(p[0], p[1]))
                }
            }
        }

        Item {
            width: root.layout.length
            height: root.lines_depth < 0 ? root.layout.depth : root.lines_depth
            clip: true

            Loader {
                active: root.inset_width > 0 && root.inset_color.a > 0
                sourceComponent: Shape {
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: root.inset_width
                        strokeColor: root.inset_color
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap
                        joinStyle: ShapePath.MiterJoin
                        miterLimit: 4
                        PathPolyline {
                            path: Drawer.stroke_path(root.layout, root.inset_gap + root.inset_width / 2).map(p => Qt.point(p[0], p[1]))
                        }
                    }
                }
            }

            Loader {
                active: root.rim_width > 0 && root.rim_color.a > 0
                sourceComponent: Shape {
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: root.rim_width
                        strokeColor: root.rim_color
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap
                        joinStyle: ShapePath.MiterJoin
                        miterLimit: 4
                        PathPolyline {
                            path: Drawer.stroke_path(root.layout, root.rim_width / 2).map(p => Qt.point(p[0], p[1]))
                        }
                    }
                }
            }
        }
    }
}
