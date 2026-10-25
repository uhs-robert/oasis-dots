import QtQuick

// A static 2x2 checker; the corner squares stay clear so it never spills past rounded corners (one radius for the top
// pair and one for the bottom pair, or each corner's own).
Item {
    id: root

    property color color: "transparent"
    property real radius: 0
    property real top_radius: 0
    property real top_left_radius: root.top_radius
    property real top_right_radius: root.top_radius
    property real bottom_left_radius: root.radius
    property real bottom_right_radius: root.radius
    // Edges that slope inward toward the bottom, like the bar's island caps.
    property real slant_left: 0
    property real slant_right: 0
    // Replaces the edges above for outlines they cannot describe: (y0, y1) => { x, w }, the span a 2px row keeps, or an
    // array of them for a row the outline splits.
    property var row_span: null

    readonly property string tile: "data:image/svg+xml;utf8," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='4' height='4'><path d='M0 0h2v2H0zM2 2h2v2H2z' fill='" + Qt.rgba(root.color.r, root.color.g, root.color.b, 1) + "' fill-opacity='" + root.color.a + "'/></svg>")
    readonly property var bands: {
        if (root.row_span) {
            const rows = [];
            for (let y = 0; y < root.height; y += 2) {
                for (const span of [].concat(root.row_span(y, y + 2)))
                    rows.push({ x: span.x, y: y, w: span.w, h: 2 });
            }
            return rows;
        }
        if (root.slant_left > 0 || root.slant_right > 0) {
            const rows = [];
            for (let y = 0; y < root.height; y += 2) {
                const t = y / root.height;
                const x = root.slant_left * t;
                rows.push({ x: x, y: y, w: root.width - x - root.slant_right * t, h: 2 });
            }
            return rows;
        }
        const top = Math.max(root.top_left_radius, root.top_right_radius), bottom = Math.max(root.bottom_left_radius, root.bottom_right_radius);
        return [
            { x: root.top_left_radius, y: 0, w: root.width - root.top_left_radius - root.top_right_radius, h: top },
            { x: 0, y: top, w: root.width, h: root.height - top - bottom },
            { x: root.bottom_left_radius, y: root.height - bottom, w: root.width - root.bottom_left_radius - root.bottom_right_radius, h: bottom }
        ];
    }

    visible: root.color.a > 0

    Repeater {
        // Counted, so a changing row_span moves the rows it has rather than rebuilding them.
        model: root.visible ? root.bands.length : 0

        Item {
            required property int index
            readonly property var band: root.bands[index]
            x: band.x
            y: band.y
            width: Math.max(0, band.w)
            height: Math.max(0, band.h)
            clip: true

            Image {
                x: -parent.x
                y: -parent.y
                width: root.width
                height: root.height
                fillMode: Image.Tile
                // Tiles start at the corner. Centred, the default, shifts them by half the size's remainder of the tile, so two
                // dithers of different sizes tiled from the same origin would not line up.
                horizontalAlignment: Image.AlignLeft
                verticalAlignment: Image.AlignTop
                smooth: false
                source: root.tile
            }
        }
    }
}
