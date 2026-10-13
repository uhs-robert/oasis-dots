// home/quickshell/.config/quickshell/components/clock_marker/EncounterSpriteMarker.qml
import QtQuick
import ".."
import "../../theme"

// nes: a pixel hourglass and 12M before a meeting; a blinking pixel "!" during one, as when a Dragon Quest encounter starts.
MarkerBase {
    id: root

    readonly property int gap: 6
    readonly property color frame_color: root.on_accent ? root.ink : Style.bar_fg
    readonly property color sand_color: root.on_accent ? root.ink : Theme.theme_secondary

    implicitWidth: Math.ceil(hourglass.implicitWidth + root.gap + digits_width.advanceWidth)
    implicitHeight: Math.max(hourglass.implicitHeight, label.implicitHeight)

    // Sized from the widest countdown, so the minutes ticking down do not resize the clock.
    TextMetrics {
        id: digits_width
        font: root.text_font
        text: "00M"
    }

    Row {
        visible: !root.in_meeting
        spacing: root.gap
        anchors.verticalCenter: parent.verticalCenter

        PixelSprite {
            id: hourglass
            anchors.verticalCenter: parent.verticalCenter
            pixel: 1
            colors: [root.frame_color, root.sand_color]
            rows: ["000000000", ".0111110.", ".0111110.", "..01110..", "...010...", "....0....", "...010...", "..01110..", ".0111110.", ".0111110.", "000000000"]
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: root.minutes + "M"
            textFormat: Text.PlainText
            color: root.frame_color
            font: root.text_font
        }
    }

    PixelSprite {
        id: alert
        visible: root.in_meeting
        anchors.verticalCenter: parent.verticalCenter
        pixel: 2
        colors: [root.frame_color, root.sand_color]
        rows: ["000", "000", "000", "000", "000", "...", "111", "111"]

        // A hard on/off blink, as the sprite would flash on a console.
        SequentialAnimation on opacity {
            running: root.in_meeting && root.visible
            loops: Animation.Infinite
            PropertyAction { value: 1 }
            PauseAnimation { duration: 500 }
            PropertyAction { value: 0 }
            PauseAnimation { duration: 500 }
            onRunningChanged: if (!running) alert.opacity = 1
        }
    }
}
