import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.theme
import qs.theme.transitions
import qs.ui.effects
import "FrameGeometry.js" as Frame

// A screen frame on one screen (FrameGeometry.js): one click-through window drawing every band but the bar's, and a
// 1x1 window per screen edge reserving that edge's zone. The bar window reserves nothing while a frame is on, so the
// zones add up the same whatever order Hyprland arranges the layers in.
Scope {
    id: root

    required property ShellScreen screen
    required property var layout
    // The line round the hole is lit on the focused monitor only, switching with the strip's (StripBackground).
    readonly property bool focused: !!Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === root.screen.name
    property color rim_color: Style.screen_frame_rim_color(root.focused)
    property color inset_color: Style.screen_frame_inset_color(root.focused)
    Behavior on rim_color {
        ColorAnimation { duration: 200 }
    }
    Behavior on inset_color {
        ColorAnimation { duration: 200 }
    }

    // A positive remainder, so a pattern's tiles start on the canonical origin's grid.
    function wrap(v, period) {
        return ((v % period) + period) % period;
    }

    PanelWindow {
        screen: root.screen
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "quickshell-frame"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // The transition captures this untransformed item, so a bottom bar's mirrored frame plays the right way up.
        Item {
            id: drawing
            anchors.fill: parent

            Item {
                width: root.layout.length
                height: root.layout.depth
                transform: Matrix4x4 {
                    matrix: {
                        const m = Frame.to_screen(root.layout);
                        return Qt.matrix4x4(m[0], m[2], 0, m[4], m[1], m[3], 0, m[5], 0, 0, 1, 0, 0, 0, 0, 1);
                    }
                }

                // Flat in the strip's colour: the strip's shade runs across the bar only.
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: -1
                        fillColor: Style.island_fill(Style.strip_color)
                        fillRule: ShapePath.OddEvenFill
                        PathMultiline {
                            paths: Frame.frame_region(root.layout).map(loop => loop.map(p => Qt.point(p[0], p[1])))
                        }
                    }
                }

                // Dither and scanlines tile from the canonical origin, as the strip's do, so they run on across the join.
                Repeater {
                    model: Style.dither.a > 0 || Style.bar_scanline_color.a > 0 ? Frame.frame_blocks(root.layout) : []

                    Item {
                        required property var modelData
                        x: modelData.x
                        y: modelData.y
                        width: modelData.w
                        height: modelData.h
                        clip: true

                        Dither {
                            x: -root.wrap(parent.x, 4)
                            y: -root.wrap(parent.y, 4)
                            width: parent.width + 4
                            height: parent.height + 4
                            color: Style.island_fill(Qt.alpha(Style.dither, Math.min(1, Style.dither.a * 2.2)))
                        }

                        Scanlines {
                            y: -root.wrap(parent.y, Style.scanline_period)
                            width: parent.width
                            height: parent.height + Style.scanline_period
                            period: Style.scanline_period
                            color: Style.island_fill(Style.bar_scanline_color)
                        }
                    }
                }

                // From Frame.stroke_clip_top down; the strip draws the rest of the line (StripBackground).
                Item {
                    y: Frame.stroke_clip_top(root.layout)
                    width: root.layout.length
                    height: root.layout.depth - y
                    clip: root.layout.has_bar

                    GapClip {
                        y: -parent.y
                        w: root.layout.length
                        h: root.layout.depth
                        gaps: ScreenFrames.drawer_rects(root.screen.name).map(r => Frame.to_canonical_rect(root.layout, r))
                        source: Component {
                            FrameStrokes {
                                layout: root.layout
                                rim_width: Style.bar_border_width
                                rim_color: root.rim_color
                                inset_gap: Style.bar_inset_gap
                                inset_width: Style.bar_inset_width
                                inset_color: root.inset_color
                            }
                        }
                    }
                }

                // The slot a kit's ornament draws in, in the canonical frame; none draw yet.
                Loader {
                    anchors.fill: parent
                    active: false
                }
            }
        }

        StyleTransition {
            anchors.fill: parent
            target: drawing
            shown: true
        }
    }

    Variants {
        model: ["top", "right", "bottom", "left"]

        delegate: Component {
            PanelWindow {
                required property string modelData

                screen: root.screen
                anchors.top: modelData === "top"
                anchors.right: modelData === "right"
                anchors.bottom: modelData === "bottom"
                anchors.left: modelData === "left"
                implicitWidth: 1
                implicitHeight: 1
                exclusiveZone: root.layout.zones[modelData]
                color: "transparent"
                mask: Region {}
                WlrLayershell.namespace: "quickshell-frame-zone"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            }
        }
    }
}
