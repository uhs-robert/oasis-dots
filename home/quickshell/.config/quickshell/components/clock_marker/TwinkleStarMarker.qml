// home/quickshell/.config/quickshell/components/clock_marker/TwinkleStarMarker.qml
import QtQuick
import "../../theme"

// oasis: a small four-point star and 12m in sand before a meeting; the same star beside MTG during one.
MarkerBase {
    id: root

    readonly property int gap: 5
    readonly property real star_size: 12
    readonly property color sand: root.on_accent ? root.ink : Theme.theme_secondary

    implicitWidth: Math.ceil(root.star_size + root.gap + Math.max(digits_width.advanceWidth, mtg_width.advanceWidth))
    implicitHeight: Math.max(root.star_size, label.implicitHeight)

    // Sized from the widest of both states, so the minutes ticking down and a meeting starting never resize the clock.
    TextMetrics {
        id: digits_width
        font: root.text_font
        text: "00m"
    }

    TextMetrics {
        id: mtg_width
        font: root.text_font
        text: "MTG"
    }

    component Star: Canvas {
        id: star
        property color fill: root.sand
        width: root.star_size
        height: root.star_size
        onFillChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const c = width / 2;
            const waist = width * 0.12;
            ctx.fillStyle = String(fill);
            ctx.beginPath();
            ctx.moveTo(c, 0);
            ctx.lineTo(c + waist, c - waist);
            ctx.lineTo(width, c);
            ctx.lineTo(c + waist, c + waist);
            ctx.lineTo(c, height);
            ctx.lineTo(c - waist, c + waist);
            ctx.lineTo(0, c);
            ctx.lineTo(c - waist, c - waist);
            ctx.closePath();
            ctx.fill();
        }
    }

    Row {
        spacing: root.gap
        anchors.verticalCenter: parent.verticalCenter

        Star { anchors.verticalCenter: parent.verticalCenter }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: Math.ceil(Math.max(digits_width.advanceWidth, mtg_width.advanceWidth))
            text: root.in_meeting ? "MTG" : root.minutes + "m"
            textFormat: Text.PlainText
            color: root.sand
            font: root.text_font
        }
    }
}
