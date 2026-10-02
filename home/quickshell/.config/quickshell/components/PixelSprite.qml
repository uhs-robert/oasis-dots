// home/quickshell/.config/quickshell/components/PixelSprite.qml
import QtQuick
import "../theme"

// Pixel art from rows of "0"-"3" (palette index) and "." (clear), painted once at an integer pixel size.
Canvas {
    id: root

    property var rows: []
    property int pixel: 2
    property var colors: [Style.shade_0, Style.shade_1, Style.shade_2, Style.shade_3]
    readonly property int columns: root.rows.length > 0 ? root.rows[0].length : 0

    implicitWidth: root.columns * root.pixel
    implicitHeight: root.rows.length * root.pixel
    width: implicitWidth
    height: implicitHeight
    antialiasing: false
    smooth: false

    onRowsChanged: root.requestPaint()
    onPixelChanged: root.requestPaint()
    onColorsChanged: root.requestPaint()

    onPaint: {
        const ctx = root.getContext("2d");
        ctx.reset();
        const p = root.pixel;
        for (let y = 0; y < root.rows.length; y++) {
            const row = root.rows[y];
            let x = 0;
            while (x < row.length) {
                const c = row[x];
                let e = x;
                while (e < row.length && row[e] === c) e++;
                if (c !== ".") {
                    ctx.fillStyle = String(root.colors[Number(c)]);
                    ctx.fillRect(x * p, y * p, (e - x) * p, p);
                }
                x = e;
            }
        }
    }
}
