// home/quickshell/.config/quickshell/components/HandCursor.qml
import QtQuick
import QtQuick.Shapes
import "../theme"

// The white glove pointing right, drawn on a 22x14 grid and scaled to the item.
Item {
    id: root

    property color color: Theme.fg_strong
    property color edge: Theme.bg_crust

    implicitWidth: 18
    implicitHeight: Math.round(root.implicitWidth * 14 / 22)

    Shape {
        width: 22
        height: 14
        preferredRendererType: Shape.CurveRenderer
        transform: Scale {
            xScale: root.width / 22
            yScale: root.height / 14
        }

        ShapePath {
            strokeWidth: 1
            strokeColor: root.edge
            fillColor: root.color
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M3 2.5 L8.6 2.5 Q10 1.5 11.6 1.5 L20 1.5 A1.8 1.8 0 0 1 20 5.1 L12.6 5.1 A1.3 1.3 0 0 1 12.6 7.7 A1.3 1.3 0 0 1 12.3 10.3 A1.25 1.25 0 0 1 11.6 12.8 L4.6 12.8 Q3 12.8 3 11.2 Z" }
        }

        ShapePath {
            strokeWidth: 1
            strokeColor: root.edge
            fillColor: root.color
            PathSvg { path: "M0.5 3 L3 3 L3 12.3 L0.5 12.3 Z" }
        }

        ShapePath {
            strokeWidth: 0.8
            strokeColor: root.edge
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathSvg { path: "M12.6 7.7 L10 7.7 M12.3 10.3 L10 10.3 M8.6 2.5 Q7.4 4.2 9.4 5.1" }
        }
    }
}
