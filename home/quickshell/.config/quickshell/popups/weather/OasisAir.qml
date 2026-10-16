import QtQuick
import QtQuick.Layouts
import qs.components.oasis as Oasis
import qs.theme
import qs.services

// Oasis Air: the 24 AQI hours as a dune ridge under a dust haze that thickens with the AQI; a palm stands on the
// cursor hour beside its value. The current AQI and the pollutants sit in cards above.
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property color sand: Theme.theme_secondary
    readonly property var slice: WeatherState.aq_hours.slice(0, 24)
    // The cursor is shared with the longer hourly range, so it is clamped to these 24 hours.
    readonly property int cursor_index: Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))
    readonly property var cursor_row: root.slice[root.cursor_index]
    readonly property var current: WeatherState.aq_current
    readonly property color current_color: root.current ? WeatherState.aqi_color(root.current.aqi) : Style.text_dim

    // Room above the ridge for the palm and its pill; the hour labels take the bottom strip.
    readonly property real top_pad: 62
    readonly property real label_h: 20
    readonly property real max_aqi: Math.max(100, ...root.slice.map(r => r.aqi))
    readonly property bool haze_live: dunes.visible && Popups.open_name === "weather"

    // Dust density 0..1: clear air has none, 150 is already a brown sky.
    function haze_of(aqi) {
        return Math.min(1, aqi / 150);
    }

    readonly property real mean_haze: {
        if (root.slice.length === 0) return 0;
        return root.slice.reduce((sum, r) => sum + root.haze_of(r.aqi), 0) / root.slice.length;
    }

    function col_w() {
        return dunes.width / Math.max(1, root.slice.length);
    }

    function x_of(i) {
        return (i + 0.5) * root.col_w();
    }

    function y_of(aqi) {
        const plot_h = dunes.height - root.top_pad - root.label_h - 6;
        return root.top_pad + plot_h * (1 - Math.min(1, aqi / root.max_aqi));
    }

    // Monotone cubic through (xs, ys) as a polyline: smooth without overshooting between hours.
    function sample_ridge(xs, ys, step) {
        const n = xs.length;
        const out = [];
        if (n < 2) return out;
        const d = [], m = [];
        for (let i = 0; i < n - 1; i++) d.push((ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]));
        m.push(d[0]);
        for (let i = 1; i < n - 1; i++) m.push(d[i - 1] * d[i] <= 0 ? 0 : 2 * d[i - 1] * d[i] / (d[i - 1] + d[i]));
        m.push(d[n - 2]);
        for (let i = 0; i < n - 1; i++) {
            const dx = xs[i + 1] - xs[i];
            for (let x = 0; x < dx; x += step) {
                const t = x / dx, t2 = t * t, t3 = t2 * t;
                out.push({
                    x: xs[i] + x,
                    y: (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * dx * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * dx * m[i + 1]
                });
            }
        }
        out.push({ x: xs[n - 1], y: ys[n - 1] });
        return out;
    }

    // Continues the open subpath when `joined`, so a fill's closing edge stays level.
    function trace_ridge(ctx, pts, dy, wobble, phase, joined) {
        for (let i = 0; i < pts.length; i++) {
            const y = pts[i].y + dy + (wobble > 0 ? wobble * Math.sin(pts[i].x / 19 + phase) : 0);
            if (i === 0 && !joined) ctx.moveTo(pts[i].x, y); else ctx.lineTo(pts[i].x, y);
        }
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const rows = root.slice;
        if (rows.length === 0) return;

        const base_y = h - root.label_h;
        const xs = [0].concat(rows.map((r, i) => root.x_of(i)), [w]);
        const vals = rows.map(r => root.y_of(r.aqi));
        const ys = [vals[0]].concat(vals, [vals[vals.length - 1]]);
        const ridge = root.sample_ridge(xs, ys, 3);

        // Dust haze: one vertical fade, drawn in 2px slices whose alpha follows the AQI between hour centres.
        const haze = ctx.createLinearGradient(0, 0, 0, base_y);
        haze.addColorStop(0, Qt.alpha(root.sand, 0));
        haze.addColorStop(0.55, Qt.alpha(root.sand, 0.5));
        haze.addColorStop(1, Qt.alpha(Theme.theme_label, 0.6));
        ctx.fillStyle = haze;
        for (let x = 0; x < w; x += 2) {
            const f = Math.max(0, Math.min(rows.length - 1, x / root.col_w() - 0.5));
            const i = Math.floor(f);
            const a = root.haze_of(rows[i].aqi);
            const b = root.haze_of(rows[Math.min(rows.length - 1, i + 1)].aqi);
            ctx.globalAlpha = 0.5 * (a + (b - a) * (f - i));
            ctx.fillRect(x, 0, 2, base_y);
        }
        ctx.globalAlpha = 1;

        // A paler dune behind the ridge, taken from earlier hours.
        const back_ys = ys.map((y, i) => base_y - (base_y - ys[Math.max(0, i - 5)]) * 0.85 - 12);
        ctx.beginPath();
        ctx.moveTo(0, base_y);
        root.trace_ridge(ctx, root.sample_ridge(xs, back_ys, 4), 0, 0, 0, true);
        ctx.lineTo(w, base_y);
        ctx.closePath();
        const back_fill = ctx.createLinearGradient(0, root.top_pad, 0, base_y);
        back_fill.addColorStop(0, Qt.alpha(Theme.theme_primary, 0.24));
        back_fill.addColorStop(1, Qt.alpha(Theme.theme_primary, 0.04));
        ctx.fillStyle = back_fill;
        ctx.fill();

        // Each hour tints the dune by its AQI band; a frame-coloured fade then sinks the colour into the sand.
        ctx.beginPath();
        ctx.moveTo(0, base_y);
        root.trace_ridge(ctx, ridge, 0, 0, 0, true);
        ctx.lineTo(w, base_y);
        ctx.closePath();
        ctx.fillStyle = Qt.alpha(Style.frame_color, 1);
        ctx.fill();
        const tint = ctx.createLinearGradient(0, 0, w, 0);
        for (let i = 0; i < rows.length; i++) tint.addColorStop(root.x_of(i) / w, Qt.alpha(WeatherState.aqi_color(rows[i].aqi), 0.4));
        ctx.fillStyle = tint;
        ctx.fill();
        const sink = ctx.createLinearGradient(0, root.top_pad, 0, base_y);
        sink.addColorStop(0, Qt.alpha(Style.frame_color, 0));
        sink.addColorStop(1, Qt.alpha(Style.frame_color, 0.85));
        ctx.fillStyle = sink;
        ctx.fill();

        ctx.save();
        ctx.beginPath();
        ctx.rect(0, 0, w, base_y);
        ctx.clip();
        ctx.lineWidth = 1;
        ctx.lineCap = "round";
        for (let k = 1; k <= 3; k++) {
            ctx.strokeStyle = Qt.alpha(root.sand, 0.2 - k * 0.04);
            ctx.beginPath();
            root.trace_ridge(ctx, ridge, k * 9, 1.6, k * 1.9);
            ctx.stroke();
        }
        ctx.restore();

        const crest = ctx.createLinearGradient(0, 0, w, 0);
        for (let i = 0; i < rows.length; i++) crest.addColorStop(root.x_of(i) / w, WeatherState.aqi_color(rows[i].aqi));
        ctx.strokeStyle = crest;
        ctx.lineWidth = 2.5;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.beginPath();
        root.trace_ridge(ctx, ridge, 0, 0, 0);
        ctx.stroke();

        const step = [1, 2, 3, 4, 6, 8, 12].find(n => n * root.col_w() >= 44) || 12;
        ctx.font = "500 " + Style.fs(-3) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "center";
        const gap = Math.ceil(44 / root.col_w());
        for (let i = 0; i < rows.length; i++) {
            const on = i === root.cursor_index;
            if (!on && (i % step !== 0 || Math.abs(i - root.cursor_index) < gap)) continue;
            const text = WeatherState.format_hour(new Date(rows[i].dt));
            const half = ctx.measureText(text).width / 2;
            ctx.fillStyle = on ? root.sand : Style.text_muted;
            ctx.fillText(text, Math.max(half, Math.min(w - half, root.x_of(i))), h - 5);
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
        spacing: 6
        visible: WeatherState.aq_has_data && !!root.current

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: aqi_card.implicitHeight
            spacing: 6

            Oasis.OasisCard {
                id: aqi_card
                Layout.fillWidth: true
                Layout.preferredWidth: 5
                Layout.minimumWidth: 0
                implicitHeight: aqi_row.implicitHeight + 16

                Rectangle {
                    x: 1
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: Math.max(0, parent.height - parent.radius * 2)
                    topRightRadius: 2
                    bottomRightRadius: 2
                    color: root.current_color
                }

                RowLayout {
                    id: aqi_row
                    anchors.fill: parent
                    anchors.margins: 8
                    anchors.leftMargin: 14
                    spacing: 8

                    Text {
                        text: root.current ? root.current.aqi : "--"
                        color: root.current_color
                        font.family: Style.number_font
                        font.pixelSize: Style.fs(20)
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 0

                        Text {
                            text: "AQI"
                            color: Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                            font.letterSpacing: 1.2
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: root.current ? WeatherState.aqi_band(root.current.aqi).label : ""
                            color: root.current_color
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-2)
                            font.weight: Font.Medium
                        }
                    }
                }
            }

            Repeater {
                model: [
                    { label: "PM2.5", key: "pm25" },
                    { label: "PM10", key: "pm10" },
                    { label: "OZONE", key: "ozone" }
                ]

                Oasis.OasisCard {
                    id: tile
                    required property var modelData
                    readonly property var value: root.current ? root.current[tile.modelData.key] : null

                    Layout.fillWidth: true
                    Layout.preferredWidth: 2
                    Layout.minimumWidth: 0
                    Layout.fillHeight: true

                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 12
                        spacing: 2

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: tile.modelData.label
                            color: Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                            font.letterSpacing: 1.2
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: tile.value !== null && tile.value !== undefined ? tile.value.toFixed(1) : "--"
                            color: Theme.fg_core
                            font.family: Style.number_font
                            font.pixelSize: Style.fs(1)
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 10

            Text {
                text: root.cursor_row ? Qt.formatDate(new Date(root.cursor_row.dt), "ddd") + " " + WeatherState.format_hour(new Date(root.cursor_row.dt)) : ""
                color: Style.text_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.cursor_row ? "AQI " + root.cursor_row.aqi + "  ·  " + WeatherState.aqi_band(root.cursor_row.aqi).label : ""
                color: Style.text_muted
                font.family: Style.number_font
                font.pixelSize: Style.fs(-2)
                font.features: { "tnum": 1 }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.25; color: Qt.alpha(root.sand, 0.35) }
                GradientStop { position: 0.75; color: Qt.alpha(root.sand, 0.35) }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: 4

            Canvas {
                id: dunes
                anchors.fill: parent
                onPaint: root.paint(getContext("2d"), width, height)
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                Connections {
                    target: WeatherState
                    function onAq_hoursChanged() { dunes.requestPaint(); }
                }
                Connections {
                    target: Style
                    function onFont_familyChanged() { dunes.requestPaint(); }
                    function onPalChanged() { dunes.requestPaint(); }
                }
                Connections {
                    target: Theme
                    function onTheme_secondaryChanged() { dunes.requestPaint(); }
                }
                Connections {
                    target: TimeFormat
                    function onH24Changed() { dunes.requestPaint(); }
                }
                Connections {
                    target: root
                    function onCursor_indexChanged() { dunes.requestPaint(); }
                }
            }

            // Drifting dust: streaks that cross the sky, more visible the thicker the haze.
            Repeater {
                model: 7

                Rectangle {
                    id: mote
                    required property int index
                    readonly property real lane: 14 + (mote.index * 23) % Math.max(20, root.top_pad + 20)
                    readonly property real span: dunes.width + 60

                    y: mote.lane
                    width: 22 + (mote.index % 3) * 14
                    height: 1.5
                    radius: 1
                    color: root.sand
                    opacity: 0.55 * root.mean_haze
                    visible: root.mean_haze > 0.08
                    x: -60

                    NumberAnimation on x {
                        running: root.haze_live && mote.visible
                        loops: Animation.Infinite
                        from: -60
                        to: mote.span
                        duration: 16000 + mote.index * 2300
                    }
                }
            }

            Item {
                id: cursor_layer
                visible: !!root.cursor_row
                readonly property real cx: root.x_of(root.cursor_index)
                readonly property real cy: root.cursor_row ? root.y_of(root.cursor_row.aqi) : 0
                readonly property color band_color: root.cursor_row ? WeatherState.aqi_color(root.cursor_row.aqi) : Style.text_dim

                Rectangle {
                    x: cursor_layer.cx - 0.5
                    y: cursor_layer.cy
                    width: 1
                    height: Math.max(0, dunes.height - root.label_h - cursor_layer.cy)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.alpha(root.sand, 0.5) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }

                Oasis.OasisPalm {
                    x: cursor_layer.cx - width / 2
                    y: cursor_layer.cy - height + 2
                    color: Theme.fg_strong
                }

                Rectangle {
                    id: pill
                    width: pill_row.implicitWidth + 18
                    height: pill_row.implicitHeight + 8
                    radius: height / 2
                    color: Qt.alpha(Theme.bg_mantle, 0.94)
                    border.width: 1
                    border.color: Qt.alpha(cursor_layer.band_color, 0.7)
                    x: Math.max(2, Math.min(dunes.width - pill.width - 2, cursor_layer.cx - pill.width / 2))
                    y: Math.max(2, cursor_layer.cy - 28 - pill.height - 3)

                    Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    Row {
                        id: pill_row
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.baseline: pill_band.baseline
                            text: root.cursor_row ? root.cursor_row.aqi : ""
                            color: cursor_layer.band_color
                            font.family: Style.number_font
                            font.pixelSize: Style.fs(0)
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }

                        Text {
                            id: pill_band
                            text: root.cursor_row ? WeatherState.aqi_band(root.cursor_row.aqi).label : ""
                            color: Style.text_dim
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
                    root.on_select(Math.max(0, Math.min(root.slice.length - 1, Math.floor(mouse.x / root.col_w()))));
                }
            }
        }
    }
}
