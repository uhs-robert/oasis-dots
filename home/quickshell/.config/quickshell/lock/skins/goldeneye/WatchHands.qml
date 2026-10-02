// home/quickshell/.config/quickshell/lock/skins/goldeneye/WatchHands.qml
import QtQuick
import QtQuick.Shapes

// The watch's pale outlined hour and minute hands and thin second hand, on the lock's 1020 x 720 plate; scale it for a smaller face.
Item {
    id: root

    property date now: new Date()
    property bool show_seconds: true
    width: 1020
    height: 720

    // One outlined bar hand with a pointed tip, pivoting on the dial centre.
    component Hand: Item {
        id: hand
        property real length: 150
        property real half: 20
        property real roof: 34
        property real tail: 26
        x: 510
        y: 360

        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 5
                strokeColor: Qt.rgba(0.69, 0.86, 0.69, 0.28)
                fillColor: Qt.rgba(0.69, 0.86, 0.69, 0.09)
                joinStyle: ShapePath.MiterJoin
                startX: 0
                startY: -hand.length
                PathLine { x: hand.half; y: -hand.length + hand.roof }
                PathLine { x: hand.half; y: hand.tail }
                PathLine { x: -hand.half; y: hand.tail }
                PathLine { x: -hand.half; y: -hand.length + hand.roof }
                PathLine { x: 0; y: -hand.length }
            }
        }
    }

    readonly property real hour_a: ((root.now.getHours() % 12) + root.now.getMinutes() / 60) * 30
    readonly property real min_a: (root.now.getMinutes() + root.now.getSeconds() / 60) * 6
    readonly property real sec_a: root.now.getSeconds() * 6

    function reach(deg) {
        const r = deg * Math.PI / 180;
        return 0.97 / Math.hypot(Math.sin(r) / 322, Math.cos(r) / 242);
    }

    Hand {
        length: root.reach(root.hour_a) * 0.66
        half: 20
        rotation: root.hour_a
    }

    Hand {
        length: root.reach(root.min_a)
        half: 16
        roof: 30
        tail: 28
        rotation: root.min_a
    }

    Rectangle {
        x: 486
        y: 366
        width: 52
        height: 28
        color: Qt.rgba(0.69, 0.86, 0.69, 0.2)
    }

    Item {
        visible: root.show_seconds
        x: 510
        y: 360
        rotation: root.sec_a

        Rectangle {
            x: -1
            y: -root.reach(root.sec_a)
            width: 2
            height: root.reach(root.sec_a) + 40
            color: Qt.rgba(0.82, 0.92, 0.82, 0.55)
        }
    }
}
