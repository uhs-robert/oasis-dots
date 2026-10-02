// home/quickshell/.config/quickshell/components/goldeneye/ScanStatic.qml
import QtQuick
import "../../services"

// A faint, steady static over a list while it is scanning; only on AC and while shown, and the shader is unloaded otherwise.
Item {
    id: root

    property bool scanning: false
    property int noise_step: 0
    readonly property bool running: root.scanning && root.visible && Power.on_ac

    Loader {
        anchors.fill: parent
        active: root.running
        sourceComponent: ShaderEffect {
            property variant source: blank
            property real level: 0.35
            property real tick: root.noise_step
            property real calm: 1
            fragmentShader: Qt.resolvedUrl("../../lock/skins/goldeneye/static.frag.qsb")
        }
    }

    ShaderEffectSource {
        id: blank
        sourceItem: blank_item
        visible: false
    }

    Item {
        id: blank_item
        width: 1
        height: 1
        visible: false
    }

    Timer {
        running: root.running
        interval: 120
        repeat: true
        onTriggered: root.noise_step += 1
    }
}
