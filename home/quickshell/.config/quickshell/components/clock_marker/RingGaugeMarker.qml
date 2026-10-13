// home/quickshell/.config/quickshell/components/clock_marker/RingGaugeMarker.qml
import QtQuick
import "../../theme"

// reticle: a hairline ring that closes as the meeting nears, beside T-minus in thin caps; in a meeting the ring is solid, with MTG.
MarkerBase {
    id: root

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    readonly property color tone: root.on_accent ? root.ink : Theme.theme_primary_light

    // Sized from the widest label, so neither the minutes nor MTG resize the clock.
    TextMetrics {
        id: upcoming_width
        font: root.text_font
        text: "T−00"
    }

    TextMetrics {
        id: mtg_width
        font: root.text_font
        text: "MTG"
    }

    Row {
        id: layout
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        Item {
            id: ring
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16

            Canvas {
                id: canvas
                anchors.fill: parent
                readonly property real fill: root.in_meeting ? 1 : root.progress
                readonly property color track: Qt.alpha(root.tone, 0.3)
                readonly property color arc: root.tone
                onFillChanged: requestPaint()
                onTrackChanged: requestPaint()
                onArcChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const c = width / 2;
                    const r = c - 1.5;
                    ctx.lineWidth = 1;
                    ctx.strokeStyle = track;
                    ctx.beginPath();
                    ctx.arc(c, c, r, 0, Math.PI * 2);
                    ctx.stroke();
                    if (fill <= 0) return;
                    ctx.lineWidth = root.in_meeting ? 2 : 1.5;
                    ctx.strokeStyle = arc;
                    ctx.beginPath();
                    ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * fill);
                    ctx.stroke();
                }
            }

            Rectangle {
                visible: root.in_meeting
                anchors.centerIn: parent
                width: 4
                height: 4
                radius: 2
                color: root.tone
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.ceil(Math.max(upcoming_width.advanceWidth, mtg_width.advanceWidth))
            text: root.in_meeting ? "MTG" : "T−" + root.minutes
            textFormat: Text.PlainText
            color: root.on_accent ? root.ink : Style.bar_fg
            font: root.text_font
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
        }
    }
}
