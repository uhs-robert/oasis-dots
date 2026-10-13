// home/quickshell/.config/quickshell/components/clock_marker/PixelSpriteMarker.qml
import QtQuick
import ".."
import "../../theme"

// snes: a pixel clock and 12M before a meeting; a filled pixel star, gently blinking, during one.
MarkerBase {
    id: root

    readonly property int gap: 6
    readonly property color line_color: root.on_accent ? root.ink : Style.bar_fg
    readonly property color star_color: root.on_accent ? root.ink : Theme.theme_secondary
    readonly property color face_color: root.on_accent ? root.ink : Theme.bg_mantle

    implicitWidth: Math.ceil(clock_sprite.implicitWidth + root.gap + digits_width.advanceWidth)
    implicitHeight: Math.max(clock_sprite.implicitHeight, label.implicitHeight)

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
            id: clock_sprite
            anchors.verticalCenter: parent.verticalCenter
            pixel: 2
            colors: [root.line_color, root.face_color]
            rows: ["..00000..", ".0011100.", "001101100", "001101100", "001100010", "001111100", "001111100", ".0011100.", "..00000.."]
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: root.minutes + "M"
            textFormat: Text.PlainText
            color: root.line_color
            font: root.text_font
        }
    }

    PixelSprite {
        id: star
        visible: root.in_meeting
        anchors.verticalCenter: parent.verticalCenter
        pixel: 2
        colors: [root.star_color, root.line_color]
        rows: ["....0....", "...000...", "...000...", "000000000", ".0000000.", "..00000..", "..00000..", ".000.000.", ".00...00."]

        SequentialAnimation on opacity {
            running: root.in_meeting && root.visible
            loops: Animation.Infinite
            NumberAnimation { to: 0.45; duration: 500; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) star.opacity = 1
        }
    }
}
