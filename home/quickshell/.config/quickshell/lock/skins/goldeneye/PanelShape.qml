// home/quickshell/.config/quickshell/lock/skins/goldeneye/PanelShape.qml
import QtQuick
import QtQuick.Shapes
import "Watch.js" as Watch

// The watch's translucent green octagon with the pale notches on its sides, at any size.
Item {
    id: root

    property real cut: 10
    property real notch_w: 8
    property real notch_h: 22
    property bool notches: true
    property color top_color: Qt.rgba(Watch.panel_top[0], Watch.panel_top[1], Watch.panel_top[2], Watch.panel_top[3])
    property color bottom_color: Qt.rgba(Watch.panel_bottom[0], Watch.panel_bottom[1], Watch.panel_bottom[2], Watch.panel_bottom[3])

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: root.height
                GradientStop { position: 0; color: root.top_color }
                GradientStop { position: 1; color: root.bottom_color }
            }
            PathPolyline {
                path: {
                    const w = root.width, h = root.height, c = Math.min(root.cut, w / 2, h / 2);
                    return [Qt.point(c, 0), Qt.point(w - c, 0), Qt.point(w, c), Qt.point(w, h - c), Qt.point(w - c, h), Qt.point(c, h), Qt.point(0, h - c), Qt.point(0, c), Qt.point(c, 0)];
                }
            }
        }
    }

    Rectangle {
        visible: root.notches
        x: 0
        y: (root.height - root.notch_h) / 2
        width: root.notch_w
        height: root.notch_h
        color: Qt.rgba(0.7, 0.78, 0.7, 0.26)
    }

    Rectangle {
        visible: root.notches
        x: root.width - root.notch_w
        y: (root.height - root.notch_h) / 2
        width: root.notch_w
        height: root.notch_h
        color: Qt.rgba(0.7, 0.78, 0.7, 0.26)
    }
}
