// home/quickshell/.config/quickshell/components/picker/LoupeReadout.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../services"

// Swatch and hex readout; the Canvas samples the centre pixel and publishes Screenshot.pixel_hex.
Row {
    id: readout

    required property var loupe
    property color hex_color: Style.text_fg

    height: Math.max(swatch.height, hex_text.implicitHeight)
    spacing: 6

    Canvas {
        id: swatch
        visible: readout.loupe.pixel_mode
        readonly property string src: readout.loupe.pixel_image
        readonly property int bx: readout.loupe.bx
        readonly property int by: readout.loupe.by
        anchors.verticalCenter: parent.verticalCenter
        width: 12
        height: 12
        onSrcChanged: if (swatch.src !== "") swatch.loadImage(swatch.src)
        onImageLoaded: swatch.requestPaint()
        onBxChanged: Qt.callLater(swatch.requestPaint)
        onByChanged: Qt.callLater(swatch.requestPaint)
        onPaint: {
            const ctx = swatch.getContext("2d");
            ctx.clearRect(0, 0, swatch.width, swatch.height);
            const w = readout.loupe.frame_size.width;
            const h = readout.loupe.frame_size.height;
            if (swatch.src === "" || !swatch.isImageLoaded(swatch.src) || w <= 0 || h <= 0) return;
            ctx.drawImage(swatch.src, Math.max(0, Math.min(w - 1, swatch.bx)), Math.max(0, Math.min(h - 1, swatch.by)), 1, 1, 0, 0, swatch.width, swatch.height);
            const d = ctx.getImageData(swatch.width / 2, swatch.height / 2, 1, 1).data;
            if (readout.loupe.screen_name !== Screenshot.cursor_screen) return;
            Screenshot.pixel_hex = "#" + [d[0], d[1], d[2]].map(v => v.toString(16).padStart(2, "0")).join("");
            Screenshot.pixel_hex_screen = readout.loupe.screen_name;
            Screenshot.pixel_hex_point = readout.loupe.at;
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 1
            border.color: Style.frame_border_color
        }
    }

    Text {
        id: hex_text
        visible: readout.loupe.pixel_mode
        anchors.verticalCenter: parent.verticalCenter
        text: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------"
        color: readout.hex_color
        font.family: Style.mono_font
        font.pixelSize: Style.fs(-3)
    }
}
