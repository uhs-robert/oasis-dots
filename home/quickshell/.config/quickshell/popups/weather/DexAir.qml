import QtQuick
import QtQuick.Layouts
import qs.components
import qs.theme
import qs.services

// The air's Pokédex entry: AQI and category as the entry, pollutants as base-stat bars, and the 24h trend as Pokégear signal bars with the needle on the cursor hour. h/l move the hour cursor.
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property var shades: Style.pixel_shades
    readonly property var slice: WeatherState.aq_hours.slice(0, 24)
    // The cursor is shared with the longer hourly range, so it is clamped to these 24 hours.
    readonly property int cursor_index: Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))
    readonly property var cursor_row: root.slice[root.cursor_index]
    readonly property bool ready: WeatherState.aq_has_data && !!WeatherState.aq_current

    readonly property int aqi: root.ready ? WeatherState.aq_current.aqi : 0
    readonly property string category: root.ready ? WeatherState.aqi_band(root.aqi).label.toUpperCase() : ""
    // The first band that is unhealthy for anyone (sensitive groups) earns the POISON type.
    readonly property int poison_from: 101
    readonly property bool poisonous: root.aqi >= root.poison_from
    readonly property int aqi_full_scale: 200

    // Concentrations in ug/m3 at which a pollutant's bar is full, roughly the "unhealthy" breakpoints.
    readonly property var pollutants: [
        { label: "PM2.5", key: "pm25", full: 150 },
        { label: "PM10", key: "pm10", full: 250 },
        { label: "OZONE", key: "ozone", full: 240 }
    ]

    // Signal bars: stacked 4px segments with a 2px gap, as in DexHourly.
    readonly property int seg_h: 4
    readonly property int seg_step: 6
    readonly property int dial_h: 14
    readonly property int label_h: 14

    function aqi_text(row) {
        return row ? "AQI " + row.aqi + " " + WeatherState.aqi_band(row.aqi).label.toUpperCase() : "";
    }

    // The radio's cursor readout, kept to the box's width by eliding.
    readonly property string radio_line: root.cursor_row ? WeatherState.format_hour(new Date(root.cursor_row.dt)).toUpperCase() + " · " + root.aqi_text(root.cursor_row) : ""

    Text {
        anchors.centerIn: parent
        visible: !WeatherState.aq_has_data
        text: WeatherState.aq_loading ? "LOADING..." : "AIR QUALITY UNAVAILABLE"
        color: root.shades[2]
        font.family: Style.font_family
        font.pixelSize: 8
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        visible: root.ready

        Item {
            Layout.fillWidth: true
            implicitHeight: 56

            PixelBox {
                anchors.fill: parent
                fill: root.shades[0]
                rings: [root.shades[2], root.shades[0], root.shades[3]]
            }

            Text {
                id: aqi_number
                x: 14
                y: Math.round((parent.height - height) / 2)
                text: String(root.aqi)
                color: root.shades[3]
                font.family: Style.font_family
                font.pixelSize: 24
            }

            ColumnLayout {
                anchors.left: aqi_number.right
                anchors.right: type_badge.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    text: "AIR · NOW"
                    color: root.shades[2]
                    font.family: Style.font_family
                    font.pixelSize: 8
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.category
                    color: root.shades[3]
                    font.family: Style.font_family
                    font.pixelSize: 8
                }

                DexStatBar {
                    Layout.fillWidth: true
                    value: root.aqi / root.aqi_full_scale
                }
            }

            // A type badge: solid POISON when the air is unhealthy, an outlined NORMAL otherwise.
            Rectangle {
                id: type_badge
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 56
                height: 16
                color: root.poisonous ? root.shades[3] : root.shades[0]
                border.width: 2
                border.color: root.poisonous ? root.shades[3] : root.shades[2]

                Text {
                    anchors.centerIn: parent
                    text: root.poisonous ? "POISON" : "NORMAL"
                    color: root.poisonous ? root.shades[0] : root.shades[2]
                    font.family: Style.font_family
                    font.pixelSize: 8
                }
            }
        }

        PixelBox {
            Layout.fillWidth: true
            implicitHeight: stats.implicitHeight + 16
            fill: root.shades[0]
            rings: [root.shades[2], root.shades[0]]

            GridLayout {
                id: stats
                anchors.fill: parent
                anchors.margins: 8
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                columns: 3
                columnSpacing: 8
                rowSpacing: 4

                Repeater {
                    model: root.pollutants

                    Item {
                        id: stat
                        required property var modelData
                        readonly property real amount: WeatherState.aq_current ? WeatherState.aq_current[stat.modelData.key] : NaN

                        Layout.columnSpan: 3
                        Layout.fillWidth: true
                        implicitHeight: 8

                        Text {
                            width: 40
                            text: stat.modelData.label
                            color: root.shades[2]
                            font.family: Style.font_family
                            font.pixelSize: 8
                        }

                        Text {
                            x: 44
                            width: 36
                            text: isNaN(stat.amount) ? "--" : stat.amount.toFixed(1)
                            color: root.shades[3]
                            font.family: Style.font_family
                            font.pixelSize: 8
                        }

                        DexStatBar {
                            anchors.left: parent.left
                            anchors.leftMargin: 88
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            value: isNaN(stat.amount) ? 0 : stat.amount / stat.modelData.full
                        }
                    }
                }
            }
        }

        PixelBox {
            Layout.fillWidth: true
            Layout.fillHeight: true
            fill: root.shades[0]
            rings: [root.shades[2], root.shades[0]]

            Text {
                x: 10
                y: -2
                leftPadding: 4
                rightPadding: 4
                text: "RADIO"
                color: root.shades[0]
                font.family: Style.font_family
                font.pixelSize: 8

                Rectangle {
                    z: -1
                    anchors.fill: parent
                    color: root.shades[2]
                }
            }

            Text {
                id: radio_readout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 10
                elide: Text.ElideRight
                text: root.radio_line
                color: root.shades[3]
                font.family: Style.font_family
                font.pixelSize: 8
            }

            Canvas {
                id: canvas
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: radio_readout.bottom
                anchors.bottom: parent.bottom
                anchors.margins: 6
                anchors.topMargin: 4

                readonly property int count: root.slice.length
                readonly property real col_w: canvas.count > 0 ? canvas.width / canvas.count : canvas.width
                readonly property int bar_w: Math.max(4, Math.floor(canvas.col_w * 0.5 / 2) * 2)
                readonly property int base_y: canvas.height - root.dial_h - root.label_h

                function x_of(i) {
                    return Math.round((i + 0.5) * canvas.col_w);
                }

                function lit_of(aqi, max_v) {
                    const max_n = Math.max(1, Math.floor(canvas.base_y / root.seg_step));
                    return Math.max(1, Math.min(max_n, Math.round(aqi / max_v * max_n)));
                }

                // Unselected bodies are a 2px checker, the top segment and the whole selected bar are solid.
                function bar_rects(ctx, x, n, selected) {
                    const half = canvas.bar_w / 2;
                    for (let k = 0; k < n; k++) {
                        const y = canvas.base_y - (k + 1) * root.seg_step + 2;
                        if (selected || k === n - 1) {
                            ctx.fillStyle = String(root.shades[3]);
                            ctx.fillRect(x, y, canvas.bar_w, root.seg_h);
                        } else {
                            ctx.fillStyle = String(root.shades[(k % 2) ? 1 : 2]);
                            ctx.fillRect(x, y, half, root.seg_h);
                            ctx.fillStyle = String(root.shades[(k % 2) ? 2 : 1]);
                            ctx.fillRect(x + half, y, half, root.seg_h);
                        }
                    }
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const rows = root.slice;
                    if (rows.length === 0) return;
                    const w = canvas.width;
                    const max_v = Math.max(100, ...rows.map(r => r.aqi));
                    ctx.font = "8px \"" + Style.font_family + "\"";
                    ctx.textAlign = "center";

                    const cursor_x = Math.round(canvas.x_of(root.cursor_index) - canvas.col_w / 2);
                    ctx.fillStyle = String(root.shades[1]);
                    ctx.fillRect(cursor_x, 0, Math.round(canvas.col_w), canvas.base_y + 2);

                    // The AQI 100 line: above it the air is unhealthy for someone.
                    const line_y = canvas.base_y - canvas.lit_of(100, max_v) * root.seg_step + 2 - 2;
                    ctx.fillStyle = String(root.shades[2]);
                    for (let x = 0; x < w; x += 8) ctx.fillRect(x, line_y, 4, 2);

                    for (let i = 0; i < rows.length; i++) {
                        const x = Math.round(canvas.x_of(i) - canvas.bar_w / 2);
                        canvas.bar_rects(ctx, x, canvas.lit_of(rows[i].aqi, max_v), i === root.cursor_index);
                    }

                    // The tuner dial: a baseline, a tick per hour (longer every third) and the hour's name under every third tick.
                    const dial_y = canvas.base_y + 2;
                    ctx.fillStyle = String(root.shades[2]);
                    ctx.fillRect(0, dial_y, w, 2);
                    for (let i = 0; i < rows.length; i++) {
                        ctx.fillRect(canvas.x_of(i) - 1, dial_y + 2, 2, i % 3 === 0 ? 8 : 4);
                    }
                    for (let i = 0; i < rows.length; i += 3) {
                        const sel = i === root.cursor_index;
                        const label = WeatherState.format_hour(new Date(rows[i].dt)).toUpperCase();
                        ctx.fillStyle = String(root.shades[sel ? 3 : 2]);
                        const half = Math.ceil(ctx.measureText(label).width / 2);
                        ctx.fillText(label, Math.max(half, Math.min(w - half, canvas.x_of(i))), canvas.height - 2);
                    }

                    // The needle on the cursor hour, with a stepped cap.
                    const nx = canvas.x_of(root.cursor_index) - 4;
                    ctx.fillStyle = String(root.shades[3]);
                    ctx.fillRect(nx, 0, 8, 2);
                    ctx.fillRect(nx + 2, 2, 4, 2);
                    ctx.fillRect(nx + 3, 4, 2, dial_y + 6 - 4);
                }

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                Connections {
                    target: root
                    function onCursor_indexChanged() { canvas.requestPaint(); }
                    function onSliceChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: Style
                    function onFont_familyChanged() { canvas.requestPaint(); }
                    function onPixel_shadesChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: TimeFormat
                    function onH24Changed() { canvas.requestPaint(); }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mouse => {
                        if (root.slice.length === 0) return;
                        root.on_select(Math.max(0, Math.min(root.slice.length - 1, Math.floor(mouse.x / canvas.col_w))));
                    }
                }
            }
        }
    }
}
