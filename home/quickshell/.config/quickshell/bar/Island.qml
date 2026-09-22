// home/quickshell/.config/quickshell/bar/Island.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

Item {
    id: root

    property color bg_color: "#232634"
    property bool cap_left: false
    property bool cap_right: false
    default property alias content: layout.children

    readonly property int cap_width: height / 2

    signal clicked

    height: 30
    width: body.width + (cap_left ? cap_width : 0) + (cap_right ? cap_width : 0)

    Rectangle {
        id: body

        x: cap_left ? root.cap_width : 0
        height: root.height
        width: layout.implicitWidth + 16
        color: root.bg_color

        RowLayout {
            id: layout
            anchors.centerIn: parent
            spacing: 8
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.clicked()
        }
    }

    Shape {
        visible: root.cap_left
        width: root.cap_width
        height: root.height
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: root.bg_color
            startX: 0
            startY: 0
            PathLine { x: root.cap_width; y: 0 }
            PathLine { x: root.cap_width; y: root.height }
            PathLine { x: 0; y: 0 }
        }
    }

    Shape {
        visible: root.cap_right
        x: root.width - root.cap_width
        width: root.cap_width
        height: root.height
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: root.bg_color
            startX: 0
            startY: 0
            PathLine { x: root.cap_width; y: 0 }
            PathLine { x: 0; y: root.height }
            PathLine { x: 0; y: 0 }
        }
    }
}
