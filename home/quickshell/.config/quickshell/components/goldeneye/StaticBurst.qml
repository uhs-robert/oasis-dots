// home/quickshell/.config/quickshell/components/goldeneye/StaticBurst.qml
import QtQuick
import "../../services"
import "../../theme"

// A short, subdued burst of the pause watch's static over whatever it covers; play() does nothing on battery or while hidden, and the shader is unloaded between bursts.
Item {
    id: root

    property real level: 0
    property int noise_step: 0
    property bool busy: false

    function play() {
        if (!Power.on_ac || !root.visible) return;
        root.noise_step = 0;
        root.busy = true;
        burst_anim.restart();
    }

    Loader {
        anchors.fill: parent
        active: root.busy
        sourceComponent: ShaderEffect {
            property variant source: blank
            property real level: root.level
            property real tick: root.noise_step
            property real calm: 1
            property real tint_amt: Style.watch_mode === "Theme" ? 1 : 0
            property color tint_col: Style.wk.mid
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
        running: root.busy
        interval: 45
        repeat: true
        onTriggered: root.noise_step += 1
    }

    SequentialAnimation {
        id: burst_anim
        NumberAnimation { target: root; property: "level"; to: 1; duration: 25 }
        PauseAnimation { duration: 100 }
        NumberAnimation { target: root; property: "level"; to: 0; duration: 25 }
        ScriptAction { script: root.busy = false }
    }
}
