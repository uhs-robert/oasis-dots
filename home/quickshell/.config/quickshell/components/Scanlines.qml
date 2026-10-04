// home/quickshell/.config/quickshell/components/Scanlines.qml
// Static 1px lines every `period` px, drawn by one shader instead of a Rectangle per line.
import QtQuick

Item {
    id: root

    property color color: "transparent"
    property int period: 3
    readonly property int count: Math.max(0, Math.ceil(root.height / root.period))

    ShaderEffect {
        visible: root.count > 0 && root.color.a > 0
        width: root.width
        // The last line may run up to 1px past the bottom, as the Rectangle rows did.
        height: Math.max(0, (root.count - 1) * root.period + 1)
        property color color: root.color
        property real period: root.period
        fragmentShader: Qt.resolvedUrl("scanlines.frag.qsb")
    }
}
