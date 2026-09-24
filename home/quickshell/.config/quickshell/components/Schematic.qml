// home/quickshell/.config/quickshell/components/Schematic.qml
import QtQuick
import QtQuick.Shapes

// A faint wireframe mech drawn on a 100 x 150 grid and scaled to the item's width.
Item {
    id: root

    property color color: "transparent"
    readonly property real k: root.width / 100

    implicitHeight: root.width * 1.5

    Shape {
        width: 100
        height: 150
        transform: Scale { xScale: root.k; yScale: root.k }
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.color
            strokeWidth: 0.7
            strokeStyle: ShapePath.DashLine
            dashPattern: [2 / 0.7, 3 / 0.7]
            fillColor: "transparent"
            PathSvg { path: "M50 2V148M10 144H90M6 36h6M6 36v6M94 36h-6M94 36v6" }
        }

        ShapePath {
            strokeColor: root.color
            strokeWidth: 1
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M42 14h16l3 8-6 5H45l-6-5zM43 20h14M34 32h32l6 16-8 22H36l-8-22zM40 40h20M36 56h28M44 44h12l-3 8h-6zM16 30h16l2 14-16 2zM84 30H68l-2 14 16 2zM18 46h8l2 28-8 2zM82 46h-8l-2 28 8 2zM16 76h14v22H16zM84 76H70v22h14zM38 70h24l-4 10H42zM40 80h8l-2 24-10-2zM36 102l10 2-4 28-8-2zM28 132h18l2 8H26zM60 80h-8l2 24 10-2zM64 102l-10 2 4 28 8-2zM72 132H54l-2 8h22z" }
        }
    }
}
