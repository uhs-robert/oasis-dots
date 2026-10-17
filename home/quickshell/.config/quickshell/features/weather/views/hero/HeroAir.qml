import QtQuick
import QtQuick.Layouts
import qs.styles.modern.widgets as Modern
import qs.theme
import qs.features.clock
import qs.features.weather

// Modern Air: a ring split into the AQI categories with a marker at the current AQI, pollutant tiles,
// and a 24 hour gradient trend with a pill tooltip riding the cursor hour.
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property var slice: WeatherState.aq_hours.slice(0, 24)
    // The cursor is shared with the longer hourly range, so it is clamped to these 24 hours.
    readonly property int cursor_index: Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))
    readonly property var cursor_row: root.slice[root.cursor_index]

    readonly property var current: WeatherState.aq_current
    readonly property color current_color: root.current ? WeatherState.aqi_color(root.current.aqi) : Style.text_dim
    readonly property color cursor_color: root.cursor_row ? WeatherState.aqi_color(root.cursor_row.aqi) : Style.text_dim

    // The ring gives every category an equal arc, so Good stays readable on a 0-500 scale;
    // the marker interpolates inside its category.
    readonly property var band_floors: [0, 51, 101, 151, 201, 301]
    readonly property real ring_start: Math.PI * 0.75
    readonly property real ring_sweep: Math.PI * 1.5

    function ring_fraction(aqi) {
        const bands = WeatherState.aqi_bands;
        let k = 0;
        while (k < bands.length - 1 && aqi >= bands[k].limit) k++;
        const floor = root.band_floors[k];
        const ceil = k === bands.length - 1 ? 500 : bands[k].limit;
        return (k + Math.max(0, Math.min(1, (aqi - floor) / (ceil - floor)))) / bands.length;
    }

    function chart_max() {
        return Math.max(100, ...root.slice.map(r => r.aqi)) * 1.1;
    }

    // Monotone cubic through (xs, ys): smooth without overshooting between hours.
    function trace_curve(ctx, xs, ys, start_with_move) {
        const n = xs.length;
        if (n === 0) return;
        if (start_with_move) ctx.moveTo(xs[0], ys[0]);
        else ctx.lineTo(xs[0], ys[0]);
        if (n === 1) return;
        const d = [], m = [];
        for (let i = 0; i < n - 1; i++) d.push((ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]));
        m.push(d[0]);
        for (let i = 1; i < n - 1; i++) m.push(d[i - 1] * d[i] <= 0 ? 0 : 2 * d[i - 1] * d[i] / (d[i - 1] + d[i]));
        m.push(d[n - 2]);
        for (let i = 0; i < n - 1; i++) {
            const dx = (xs[i + 1] - xs[i]) / 3;
            ctx.bezierCurveTo(xs[i] + dx, ys[i] + m[i] * dx, xs[i + 1] - dx, ys[i + 1] - m[i + 1] * dx, xs[i + 1], ys[i + 1]);
        }
    }

    component PollutantTile: Modern.CardSurface {
        id: tile
        property string label: ""
        property var value: null
        property string unit: "µg/m³"

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: tile_col.implicitHeight + 14

        ColumnLayout {
            id: tile_col
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 0

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: tile.label
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: tile.value !== null ? tile.value.toFixed(1) : "--"
                    color: Style.text_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(2)
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBaseline
                    elide: Text.ElideRight
                    text: tile.unit
                    color: Style.text_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !WeatherState.aq_has_data
        text: WeatherState.aq_loading ? "Loading…" : "Air quality unavailable"
        color: Style.text_dim
        font.family: Style.font_family
        font.pixelSize: Style.font_size
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        visible: WeatherState.aq_has_data && !!root.current

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 14

            Item {
                id: ring
                Layout.preferredWidth: Style.px(112)
                Layout.preferredHeight: Style.px(112)

                Canvas {
                    id: ring_canvas
                    anchors.fill: parent

                    onWidthChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const cx = width / 2, cy = height / 2;
                        const thick = 10;
                        const r = Math.min(width, height) / 2 - thick;
                        const bands = WeatherState.aqi_bands;
                        const seg = root.ring_sweep / bands.length;
                        const gap = 0.05;

                        ctx.lineWidth = thick;
                        ctx.lineCap = "round";
                        for (let k = 0; k < bands.length; k++) {
                            const a0 = root.ring_start + k * seg + gap;
                            const a1 = root.ring_start + (k + 1) * seg - gap;
                            ctx.strokeStyle = Qt.alpha(WeatherState.color_for_key(bands[k].color_key), root.current && WeatherState.aqi_band(root.current.aqi) === bands[k] ? 1 : 0.38);
                            ctx.beginPath();
                            ctx.arc(cx, cy, r, a0, a1);
                            ctx.stroke();
                        }

                        if (!root.current) return;
                        const a = root.ring_start + root.ring_fraction(root.current.aqi) * root.ring_sweep;
                        const mx = cx + Math.cos(a) * r, my = cy + Math.sin(a) * r;
                        ctx.fillStyle = Qt.alpha(root.current_color, 0.3);
                        ctx.beginPath();
                        ctx.arc(mx, my, thick * 0.95, 0, Math.PI * 2);
                        ctx.fill();
                        ctx.fillStyle = Theme.fg_strong;
                        ctx.strokeStyle = root.current_color;
                        ctx.lineWidth = 3;
                        ctx.beginPath();
                        ctx.arc(mx, my, thick * 0.5, 0, Math.PI * 2);
                        ctx.fill();
                        ctx.stroke();
                    }

                    Connections {
                        target: WeatherState
                        function onAq_currentChanged() { ring_canvas.requestPaint(); }
                    }
                    Connections {
                        target: Style
                        function onPalChanged() { ring_canvas.requestPaint(); }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: -2

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.current ? root.current.aqi : "--"
                        color: root.current_color
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(14)
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "US AQI"
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-4)
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.6
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Rectangle {
                    Layout.preferredWidth: cat_text.implicitWidth + 18
                    Layout.maximumWidth: parent.width
                    Layout.preferredHeight: cat_text.implicitHeight + 8
                    radius: height / 2
                    color: Qt.alpha(root.current_color, 0.16)
                    border.width: 1
                    border.color: Qt.alpha(root.current_color, 0.45)

                    Text {
                        id: cat_text
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: root.current ? WeatherState.aqi_band(root.current.aqi).label : ""
                        color: root.current_color
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-1)
                        font.weight: Font.DemiBold
                    }
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.cursor_row ? WeatherState.format_hour(new Date(root.cursor_row.dt)) + "  ·  AQI " + root.cursor_row.aqi : ""
                    color: Style.text_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-1)
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.cursor_row ? WeatherState.aqi_band(root.cursor_row.aqi).label : ""
                    color: root.cursor_color
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            PollutantTile { label: "PM2.5"; value: root.current ? root.current.pm25 : null }
            PollutantTile { label: "PM10"; value: root.current ? root.current.pm10 : null }
            PollutantTile { label: "OZONE"; value: root.current ? root.current.ozone : null }
        }

        Item {
            id: plot
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: 4

            readonly property real top_pad: 28
            readonly property real bottom_pad: 18
            readonly property real plot_h: plot.height - plot.top_pad - plot.bottom_pad
            readonly property real col_w: root.slice.length > 0 ? plot.width / root.slice.length : plot.width

            function x_of(i) {
                return (i + 0.5) * plot.col_w;
            }

            function y_of(aqi) {
                return plot.top_pad + plot.plot_h - Math.min(1, aqi / root.chart_max()) * plot.plot_h;
            }

            Canvas {
                id: canvas
                anchors.fill: parent

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const rows = root.slice;
                    if (rows.length === 0) return;
                    const w = width, h = height;
                    const base_y = plot.top_pad + plot.plot_h;
                    const xs = rows.map((r, i) => plot.x_of(i));
                    const ys = rows.map(r => plot.y_of(r.aqi));

                    ctx.lineWidth = 1;
                    ctx.strokeStyle = Qt.alpha(Theme.fg_strong, 0.07);
                    for (let g = 0; g <= 3; g++) {
                        const gy = Math.round(plot.top_pad + plot.plot_h * g / 3) + 0.5;
                        ctx.beginPath();
                        ctx.moveTo(0, gy);
                        ctx.lineTo(w, gy);
                        ctx.stroke();
                    }

                    // Each category holds its colour across its AQI span and blends only near the thresholds,
                    // so the line shows which category every hour reaches.
                    const bands = WeatherState.aqi_bands;
                    const max_v = root.chart_max();
                    const stroke = ctx.createLinearGradient(0, base_y, 0, plot.top_pad);
                    const fill = ctx.createLinearGradient(0, base_y, 0, plot.top_pad);
                    const blend = 0.03;
                    for (let k = 0; k < bands.length; k++) {
                        const lo = root.band_floors[k] / max_v;
                        const hi = Math.min(1, bands[k].limit / max_v);
                        if (lo >= 1) break;
                        const c = WeatherState.color_for_key(bands[k].color_key);
                        const a = Math.min(hi, lo + blend);
                        const b = Math.max(a, hi - blend);
                        for (const pos of k === 0 ? [0, b] : [a, b]) {
                            stroke.addColorStop(pos, c);
                            fill.addColorStop(pos, Qt.alpha(c, 0.12 + 0.4 * pos));
                        }
                        if (hi >= 1) {
                            stroke.addColorStop(1, c);
                            fill.addColorStop(1, Qt.alpha(c, 0.52));
                        }
                    }

                    ctx.beginPath();
                    ctx.moveTo(xs[0], base_y);
                    root.trace_curve(ctx, xs, ys, false);
                    ctx.lineTo(xs[xs.length - 1], base_y);
                    ctx.closePath();
                    ctx.fillStyle = fill;
                    ctx.fill();

                    ctx.strokeStyle = stroke;
                    ctx.lineWidth = 2.5;
                    ctx.lineJoin = "round";
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    root.trace_curve(ctx, xs, ys, true);
                    ctx.stroke();

                    ctx.font = "600 " + Style.fs(-3) + "px \"" + Style.font_family + "\"";
                    ctx.textAlign = "center";
                    ctx.fillStyle = Style.text_muted;
                    const label_w = ctx.measureText(WeatherState.format_hour(new Date(2000, 0, 1, 12))).width + 10;
                    const step = [2, 3, 4, 6, 8, 12].find(n => n * plot.col_w >= label_w) || 12;
                    for (let i = 0; i < rows.length; i += step) {
                        ctx.fillText(WeatherState.format_hour(new Date(rows[i].dt)), xs[i], h - 3);
                    }
                }

                Connections {
                    target: WeatherState
                    function onAq_hoursChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: Style
                    function onFont_familyChanged() { canvas.requestPaint(); }
                    function onFont_sizeChanged() { canvas.requestPaint(); }
                    function onPalChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: TimeFormat
                    function onH24Changed() { canvas.requestPaint(); }
                }
            }

            Item {
                id: cursor_layer
                visible: !!root.cursor_row
                readonly property real cx: plot.x_of(root.cursor_index)
                readonly property real cy: root.cursor_row ? plot.y_of(root.cursor_row.aqi) : 0

                Rectangle {
                    x: cursor_layer.cx - 0.5
                    y: cursor_layer.cy
                    width: 1
                    height: plot.top_pad + plot.plot_h - cursor_layer.cy
                    color: Qt.alpha(root.cursor_color, 0.55)
                }

                Rectangle {
                    x: cursor_layer.cx - 9
                    y: cursor_layer.cy - 9
                    width: 18
                    height: 18
                    radius: 9
                    color: Qt.alpha(root.cursor_color, 0.25)
                }

                Rectangle {
                    x: cursor_layer.cx - 5
                    y: cursor_layer.cy - 5
                    width: 10
                    height: 10
                    radius: 5
                    color: Style.text_strong
                    border.width: 3
                    border.color: root.cursor_color
                }

                Modern.CardSurface {
                    id: tooltip
                    selected: true
                    radius: height / 2
                    width: tip_row.implicitWidth + 22
                    height: tip_row.implicitHeight + 10
                    readonly property bool below: cursor_layer.cy - tooltip.height - 12 < 0
                    x: Math.max(2, Math.min(plot.width - tooltip.width - 2, cursor_layer.cx - tooltip.width / 2))
                    y: tooltip.below ? cursor_layer.cy + 14 : cursor_layer.cy - tooltip.height - 12

                    Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    RowLayout {
                        id: tip_row
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            Layout.alignment: Qt.AlignBaseline
                            text: root.cursor_row ? root.cursor_row.aqi : ""
                            color: Style.text_strong
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(0)
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }

                        Text {
                            Layout.alignment: Qt.AlignBaseline
                            text: root.cursor_row ? WeatherState.aqi_band(root.cursor_row.aqi).label : ""
                            color: root.cursor_color
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-3)
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: mouse => {
                    if (root.slice.length === 0) return;
                    root.on_select(Math.max(0, Math.min(root.slice.length - 1, Math.floor(mouse.x / plot.col_w))));
                }
            }
        }
    }
}
