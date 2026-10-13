// home/quickshell/.config/quickshell/components/clock_marker/PixelBellMarker.qml
import QtQuick
import ".."
import "../../theme"

// gameboy: a pixel bell and 12M before a meeting; the bell swinging from its top during one.
MarkerBase {
    id: root

    readonly property int gap: 6
    readonly property color body_color: root.on_accent ? root.ink : Style.pixel_shades[3]
    readonly property color shine_color: root.on_accent ? root.ink : Style.pixel_shades[2]
    readonly property var bell_rows: ["....0....", "...000...", "..01100..", ".0110000.", ".0110000.", "000000000", ".........", "...000..."]

    implicitWidth: Math.ceil(upcoming_bell.implicitWidth + root.gap + digits_width.advanceWidth)
    implicitHeight: Math.max(upcoming_bell.implicitHeight, label.implicitHeight)

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
            id: upcoming_bell
            anchors.verticalCenter: parent.verticalCenter
            pixel: 2
            colors: [root.body_color, root.shine_color]
            rows: root.bell_rows
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: root.minutes + "M"
            textFormat: Text.PlainText
            color: root.body_color
            font: root.text_font
        }
    }

    Item {
        visible: root.in_meeting
        anchors.centerIn: parent
        width: swing_bell.implicitWidth
        height: swing_bell.implicitHeight

        PixelSprite {
            id: swing_bell
            pixel: 2
            colors: [root.body_color, root.shine_color]
            rows: root.bell_rows
            transformOrigin: Item.Top
            antialiasing: false

            SequentialAnimation on rotation {
                running: root.in_meeting && root.visible
                loops: Animation.Infinite
                NumberAnimation { to: 16; duration: 500; easing.type: Easing.InOutSine }
                NumberAnimation { to: -16; duration: 500; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running) swing_bell.rotation = 0
            }
        }
    }
}
