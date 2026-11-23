import QtQuick
import qs.core
import qs.theme

// The PS2 instrument rail: a chrome strip with a neon wire beside it, down one edge of a slab. An optional lit
// segment (`lit_y`, `lit_h`; none while `lit_h` is 0) slides to follow a selection. `fire()` runs one bright pulse
// down the wire; the caller calls it on a real event and nothing loops.
Item {
    id: root

    property real lit_y: 0
    property real lit_h: 0
    property real pulse: -1
    // Nothing animates on battery or while hidden: the lit segment then jumps and fire() does nothing.
    readonly property bool animates: PowerSource.on_ac && root.visible
    readonly property real pulse_len: Math.max(24, root.height * 0.18)

    implicitWidth: 10

    function fire() {
        if (root.animates) pulse_anim.restart();
    }

    onAnimatesChanged: if (!root.animates) pulse_anim.stop()

    NumberAnimation {
        id: pulse_anim
        target: root
        property: "pulse"
        from: 0
        to: 1
        duration: 900
        easing.type: Easing.InOutSine
        onStopped: root.pulse = -1
    }

    Rectangle {
        y: 4
        width: 4
        height: root.height - 8
        radius: 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary_light, 0.85) }
            GradientStop { position: 0.5; color: Qt.alpha(Theme.theme_primary_strong, 0.55) }
            GradientStop { position: 1; color: Qt.alpha(Theme.bg_shadow, 0.5) }
        }
    }

    Rectangle {
        x: 7
        y: 4
        width: 1
        height: root.height - 8
        color: Qt.alpha(Theme.theme_primary, 0.35)
    }

    Rectangle {
        visible: root.lit_h > 0
        y: root.lit_y
        width: 4
        height: root.lit_h
        radius: 2
        color: Qt.alpha(Theme.theme_primary_light, 0.9)

        Behavior on y {
            enabled: root.animates
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Behavior on height {
            enabled: root.animates
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        visible: root.pulse >= 0
        readonly property real head: 4 + (root.height - 8) * root.pulse
        x: 6.5
        y: Math.max(4, head - root.pulse_len)
        width: 2
        height: Math.max(0, head - y)
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Qt.alpha(Theme.fg_strong, 0.95) }
        }
    }
}
