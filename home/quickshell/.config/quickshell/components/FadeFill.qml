// home/quickshell/.config/quickshell/components/FadeFill.qml
import QtQuick

// A fill that fades out to the right.
Rectangle {
    id: root

    property color fill: "transparent"

    anchors.fill: parent
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: root.fill }
        GradientStop { position: 1; color: Qt.alpha(root.fill, 0) }
    }
}
