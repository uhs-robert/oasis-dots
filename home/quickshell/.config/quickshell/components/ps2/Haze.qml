// home/quickshell/.config/quickshell/components/ps2/Haze.qml
import QtQuick
import "../../theme"
import "../../popups/weather" as Weather

// The PS2 boot-screen backdrop, static: faint translucent towers standing on a hazy horizon.
Item {
    id: root

    // The horizon's height from the top, as a fraction.
    property real horizon: 0.72
    property int towers: 9
    property real strength: 1
    readonly property real horizon_y: Math.round(root.height * root.horizon)

    clip: true

    Weather.TowerFloor {
        y: root.horizon_y - haze_h
        width: root.width
        height: root.height - y
        haze_h: Math.min(40, root.horizon_y)
        opacity: root.strength
    }

    Repeater {
        model: root.towers

        Item {
            id: tower
            required property int index
            // Fixed heights and spacing so the skyline never shifts between opens.
            readonly property real rise: [0.55, 0.3, 0.8, 0.42, 0.65, 0.25, 0.9, 0.38, 0.6, 0.48, 0.72, 0.33][tower.index % 12]
            readonly property real slot: root.width / root.towers
            x: tower.slot * tower.index + tower.slot * 0.28
            width: Math.max(6, tower.slot * 0.44)
            height: root.horizon_y * tower.rise
            y: root.horizon_y - height
            opacity: (0.18 + 0.1 * (tower.index % 3)) * root.strength

            Rectangle {
                anchors.fill: parent
                radius: 2
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary_light, 0.8) }
                    GradientStop { position: 0.35; color: Qt.alpha(Theme.theme_primary_strong, 0.5) }
                    GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary_strong, 0.1) }
                }
            }

            Rectangle {
                anchors.right: parent.right
                width: parent.width * 0.38
                height: parent.height
                radius: 2
                color: Qt.alpha(Theme.bg_shadow, 0.3)
            }

            Rectangle {
                anchors.top: parent.bottom
                width: parent.width
                height: Math.min(14, parent.height * 0.3)
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary_strong, 0.35) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }
    }
}
