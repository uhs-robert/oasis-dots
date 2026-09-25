// home/quickshell/.config/quickshell/components/ps2/ClockScreen.qml
import QtQuick
import Quickshell
import "../../theme"
import "../../services"

// The PS2 clock screen: a big thin digital clock floating over the tower haze, the date and zone beneath.
Item {
    id: root

    property bool running: false
    readonly property date now: Timezones.shift(clock.date)

    implicitHeight: Style.px(118)

    SystemClock {
        id: clock
        enabled: root.running
        precision: SystemClock.Seconds
    }

    function pad2(n) {
        return n < 10 ? "0" + n : "" + n;
    }

    Haze {
        anchors.fill: parent
        horizon: 0.82
        towers: 11
        strength: 0.8
    }

    Rectangle {
        anchors.centerIn: digits
        width: digits.width * 1.6
        height: digits.height * 1.4
        radius: height / 2
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.alpha(Theme.theme_primary, 0.16) }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    Row {
        id: digits
        anchors.horizontalCenter: parent.horizontalCenter
        y: Style.px(6)
        spacing: 4

        Text {
            text: root.pad2(root.now.getHours() % 12 || 12) + ":" + root.pad2(root.now.getMinutes())
            color: Theme.fg_strong
            font.family: Style.font_family
            font.pixelSize: Style.font_size * 3
            font.weight: Font.ExtraLight
            font.features: { "tnum": 1 }
        }

        Column {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.font_size * 0.5
            spacing: 0

            Text {
                text: root.pad2(root.now.getSeconds())
                color: Theme.theme_primary_light
                font.family: Style.font_family
                font.pixelSize: Style.font_size
                font.weight: Font.Light
                font.features: { "tnum": 1 }
            }

            Text {
                text: root.now.getHours() < 12 ? "AM" : "PM"
                color: Theme.theme_primary_light
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 1.2
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: digits.bottom
        anchors.topMargin: -2
        text: Qt.formatDate(root.now, "dddd, MMMM d") + (Timezones.abbrev !== "" && !Timezones.is_local ? "  ·  " + Timezones.abbrev : "")
        color: Theme.theme_primary_light
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.5
    }
}
