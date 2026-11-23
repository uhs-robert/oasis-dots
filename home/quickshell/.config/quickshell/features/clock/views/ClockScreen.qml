import QtQuick
import Quickshell
import qs.theme
import qs.features.clock
import qs.styles.ps2.widgets

// The PS2 clock screen: a big thin digital clock with the minute and hour rings beside it, the date and zone beneath.
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

    readonly property real group_gap: Style.px(14)
    readonly property int minute: root.now.getMinutes()
    // The ring flashes on the minute the clock moves to, not when the screen opens or the zone is switched.
    onMinuteChanged: if (root.running) rings.fire()

    TimeRings {
        id: rings
        // The rings and the digits sit side by side as one group, centred, so nothing draws behind the digits.
        x: Math.max(Style.px(8), Math.round((root.width - (rings.width + root.group_gap + digits.width)) / 2))
        anchors.verticalCenter: parent.verticalCenter
        width: parent.height - Style.px(12)
        minute: root.minute
        hour: root.now.getHours() % 12
    }

    Rectangle {
        anchors.centerIn: digits
        width: digits.width * 1.25
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
        x: rings.x + rings.width + root.group_gap
        y: Style.px(6)
        spacing: 4

        Text {
            text: TimeFormat.digits(root.now, false)
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
                visible: !TimeFormat.h24
                text: TimeFormat.meridiem(root.now)
                color: Theme.theme_primary_light
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 1.2
            }
        }
    }

    Text {
        anchors.horizontalCenter: digits.horizontalCenter
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
