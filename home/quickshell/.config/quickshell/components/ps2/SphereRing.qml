// home/quickshell/.config/quickshell/components/ps2/SphereRing.qml
import QtQuick
import "../../theme"

// The Audio CD player ring: spheres around a circle, lit clockwise from the top up to `value`, a readout in the middle.
Item {
    id: root

    property real value: 0
    property int count: 16
    property bool dimmed: false
    property string label: ""
    property string caption: ""
    property real sphere: Math.max(6, root.width * 0.1)
    readonly property int lit_count: Math.round(Math.max(0, Math.min(1, root.value)) * root.count)
    readonly property real orbit: root.width / 2 - root.sphere

    implicitWidth: 96
    implicitHeight: root.width
    opacity: root.dimmed ? 0.5 : 1

    Rectangle {
        anchors.centerIn: parent
        width: root.orbit * 1.5
        height: width
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary, 0.14) }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    Repeater {
        model: root.count

        Sphere {
            required property int index
            readonly property real a: index / root.count * Math.PI * 2 - Math.PI / 2
            width: root.sphere
            x: root.width / 2 + root.orbit * Math.cos(a) - width / 2
            y: root.height / 2 + root.orbit * Math.sin(a) - width / 2
            lit: index < root.lit_count
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: -2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Theme.fg_strong
            font.family: "Exo 2"
            font.pixelSize: Math.round(root.width * 0.22)
            font.weight: Font.ExtraLight
        }

        Text {
            visible: root.caption !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.caption
            color: Theme.theme_primary_light
            font.family: "Exo 2"
            font.pixelSize: Math.max(8, Math.round(root.width * 0.085))
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2
        }
    }
}
