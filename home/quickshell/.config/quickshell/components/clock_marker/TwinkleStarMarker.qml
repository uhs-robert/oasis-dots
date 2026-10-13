// home/quickshell/.config/quickshell/components/clock_marker/TwinkleStarMarker.qml
import QtQuick
import "../../theme"

// oasis: a small four-point star and 12m in sand before a meeting; the star twinkling during one.
MarkerBase {
    id: root

    readonly property int gap: 5
    readonly property real star_size: 12
    readonly property color sand: root.on_accent ? root.ink : Theme.theme_secondary

    implicitWidth: Math.ceil(root.star_size + root.gap + digits_width.advanceWidth)
    implicitHeight: Math.max(root.star_size, label.implicitHeight)

    // Sized from the widest countdown, so the minutes ticking down do not resize the clock.
    TextMetrics {
        id: digits_width
        font: root.text_font
        text: "00m"
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
        visible: !root.in_meeting
        spacing: root.gap
        anchors.verticalCenter: parent.verticalCenter

        Star { anchors.verticalCenter: parent.verticalCenter }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: root.minutes + "m"
            textFormat: Text.PlainText
            color: root.sand
            font: root.text_font
        }
    }

    Star {
        id: twinkle
        visible: root.in_meeting
        anchors.verticalCenter: parent.verticalCenter

        SequentialAnimation {
            running: root.in_meeting && root.visible
            loops: Animation.Infinite
            ParallelAnimation {
                NumberAnimation { target: twinkle; property: "scale"; to: 1.35; duration: 500; easing.type: Easing.InOutSine }
                NumberAnimation { target: twinkle; property: "opacity"; to: 1; duration: 500; easing.type: Easing.InOutSine }
            }
            ParallelAnimation {
                NumberAnimation { target: twinkle; property: "scale"; to: 0.7; duration: 500; easing.type: Easing.InOutSine }
                NumberAnimation { target: twinkle; property: "opacity"; to: 0.4; duration: 500; easing.type: Easing.InOutSine }
            }
            onRunningChanged: if (!running) { twinkle.scale = 1; twinkle.opacity = 1; }
        }
    }
}
