pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.components
import qs.theme
import qs.services

// Hourly's Air sub-view: the US AQI as a ring gauge split into its category bands, a small ring per pollutant,
// then the 24h trend as a hairline trace over a ring per hour with the cursor hour framed by a reticle. h/l move the hour cursor.
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property color ink: Style.text_strong
    readonly property real gauge_size: 104
    readonly property real pollutant_size: 46
    readonly property real mini_size: 13
    readonly property real reticle_size: 34
    // The ring spans six equal band segments; the last band's top is the AQI scale's end.
    readonly property real aqi_max: 500
    readonly property real band_gap_deg: 5

    readonly property var slice: WeatherState.aq_hours.slice(0, 24)
    // The cursor is shared with the longer hourly range, so it is clamped to these 24 hours.
    readonly property int cursor_index: Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))
    readonly property var cursor_row: root.slice[root.cursor_index]
    readonly property var cur: WeatherState.aq_current
    readonly property bool ready: WeatherState.aq_has_data && !!root.cur
    readonly property real trace_max: Math.max(100, ...root.slice.map(r => r.aqi))

    function band_low(i) {
        return i === 0 ? 0 : WeatherState.aqi_bands[i - 1].limit;
    }

    function band_high(i) {
        const limit = WeatherState.aqi_bands[i].limit;
        return limit === Infinity ? root.aqi_max : limit;
    }

    // How far through band i the reading has got, 0 to 1.
    function band_fill(i, aqi) {
        return Math.max(0, Math.min(1, (aqi - root.band_low(i)) / (root.band_high(i) - root.band_low(i))));
    }

    function aqi_fraction(aqi) {
        return Math.max(0, Math.min(1, aqi / 300));
    }

    function trace_y(aqi, h) {
        return 4 + (h - 8) * (1 - Math.min(1, aqi / root.trace_max));
    }

    function paint_trace(ctx, w, h) {
        ctx.reset();
        const rows = root.slice;
        if (rows.length === 0) return;
        const col_w = w / rows.length;
        const x_of = i => (i + 0.5) * col_w;

        ctx.strokeStyle = Style.hairline_dim;
        ctx.lineWidth = 1;
        ctx.setLineDash([1, 4]);
        for (const guide of [50, 100, 150, 200]) {
            if (guide > root.trace_max) continue;
            const y = Math.round(root.trace_y(guide, h)) + 0.5;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(w, y);
            ctx.stroke();
        }
        ctx.setLineDash([]);

        ctx.strokeStyle = root.ink;
        ctx.lineJoin = "round";
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        for (let i = 0; i < rows.length; i++) {
            if (i === 0) ctx.moveTo(x_of(i), root.trace_y(rows[i].aqi, h)); else ctx.lineTo(x_of(i), root.trace_y(rows[i].aqi, h));
        }
        ctx.stroke();

        // Samples are small open rings in their hour's band colour.
        ctx.fillStyle = Style.frame_color;
        ctx.lineWidth = 1.2;
        for (let i = 0; i < rows.length; i++) {
            ctx.strokeStyle = WeatherState.aqi_color(rows[i].aqi);
            ctx.beginPath();
            ctx.arc(x_of(i), root.trace_y(rows[i].aqi, h), 2.5, 0, 2 * Math.PI);
            ctx.fill();
            ctx.stroke();
        }
    }

    component CapsLabel: Text {
        color: Style.text_muted
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 2.5
    }

    // A faint track lit clockwise from the top over `fraction`, with the reading inside.
    component PollutantRing: Item {
        id: pollutant
        property string label: ""
        property var value: null
        property real full_scale: 100

        readonly property real fraction: pollutant.value === null ? 0 : Math.max(0, Math.min(1, pollutant.value / pollutant.full_scale))
        readonly property real r: root.pollutant_size / 2 - 3

        implicitWidth: root.pollutant_size
        implicitHeight: root.pollutant_size + caption.implicitHeight + 3

        Shape {
            x: (pollutant.width - root.pollutant_size) / 2
            width: root.pollutant_size
            height: root.pollutant_size
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 1
                strokeColor: Qt.alpha(root.ink, 0.2)
                fillColor: "transparent"
                PathAngleArc { centerX: root.pollutant_size / 2; centerY: root.pollutant_size / 2; radiusX: pollutant.r; radiusY: pollutant.r; startAngle: 0; sweepAngle: 360 }
            }

            ShapePath {
                strokeWidth: pollutant.fraction > 0 ? 2 : -1
                strokeColor: root.ink
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathAngleArc { centerX: root.pollutant_size / 2; centerY: root.pollutant_size / 2; radiusX: pollutant.r; radiusY: pollutant.r; startAngle: -90; sweepAngle: 360 * pollutant.fraction }
            }
        }

        Text {
            x: (pollutant.width - width) / 2
            y: (root.pollutant_size - height) / 2
            text: pollutant.value !== null ? pollutant.value.toFixed(1) : "--"
            color: Style.text_strong
            font.family: Style.number_font
            font.pixelSize: Style.fs(-4)
        }

        CapsLabel {
            id: caption
            x: (pollutant.width - width) / 2 + 1
            y: root.pollutant_size + 3
            text: pollutant.label
            font.letterSpacing: 1.5
        }
    }

    CapsLabel {
        anchors.centerIn: parent
        visible: !root.ready
        text: WeatherState.aq_loading ? "Loading" : "Air quality unavailable"
        color: Style.text_dim
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        visible: root.ready

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Item {
                id: gauge
                Layout.preferredWidth: root.gauge_size
                Layout.preferredHeight: root.gauge_size
                readonly property color tone: root.ready ? WeatherState.aqi_color(root.cur.aqi) : Style.text_dim

                Repeater {
                    model: WeatherState.aqi_bands.length

                    Shape {
                        id: band
                        required property int index
                        readonly property real slot: 360 / WeatherState.aqi_bands.length
                        readonly property color tone: WeatherState.color_for_key(WeatherState.aqi_bands[band.index].color_key)
                        readonly property real fill: root.ready ? root.band_fill(band.index, root.cur.aqi) : 0
                        readonly property real start: -90 + band.index * band.slot + root.band_gap_deg / 2
                        readonly property real span: band.slot - root.band_gap_deg
                        readonly property real r: root.gauge_size / 2 - 4

                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: 1.5
                            strokeColor: Qt.alpha(band.tone, 0.3)
                            fillColor: "transparent"
                            capStyle: ShapePath.FlatCap
                            PathAngleArc { centerX: root.gauge_size / 2; centerY: root.gauge_size / 2; radiusX: band.r; radiusY: band.r; startAngle: band.start; sweepAngle: band.span }
                        }

                        ShapePath {
                            strokeWidth: band.fill > 0 ? 4 : -1
                            strokeColor: band.tone
                            fillColor: "transparent"
                            capStyle: ShapePath.FlatCap
                            PathAngleArc { centerX: root.gauge_size / 2; centerY: root.gauge_size / 2; radiusX: band.r; radiusY: band.r; startAngle: band.start; sweepAngle: band.span * band.fill }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.ready ? root.cur.aqi : "--"
                        color: gauge.tone
                        font.family: Style.number_font
                        font.weight: Font.ExtraLight
                        font.pixelSize: Style.fs(9)
                    }

                    CapsLabel {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "US AQI"
                        font.pixelSize: Style.fs(-6)
                        font.letterSpacing: 2
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.ready ? WeatherState.aqi_band(root.cur.aqi).label.toUpperCase() : ""
                    color: gauge.tone
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                    font.letterSpacing: 2
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PollutantRing { Layout.fillWidth: true; Layout.preferredWidth: 0; label: "PM2.5"; value: root.cur ? root.cur.pm25 : null; full_scale: 55 }
                    PollutantRing { Layout.fillWidth: true; Layout.preferredWidth: 0; label: "PM10"; value: root.cur ? root.cur.pm10 : null; full_scale: 255 }
                    PollutantRing { Layout.fillWidth: true; Layout.preferredWidth: 0; label: "OZONE"; value: root.cur ? root.cur.ozone : null; full_scale: 200 }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Style.hairline }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            readonly property var r: root.cursor_row
            text: r ? WeatherState.format_hour(new Date(r.dt)).toUpperCase() + " · AQI " + r.aqi + " · " + WeatherState.aqi_band(r.aqi).label.toUpperCase() : ""
            color: Style.text_muted
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
            font.letterSpacing: 2.5
        }

        Item {
            id: trend
            Layout.fillWidth: true
            Layout.fillHeight: true
            readonly property real col_w: trend.width / Math.max(1, root.slice.length)
            readonly property real ring_top: trend.height - root.reticle_size - label_row.height - 2
            // Every few hours get a label, as many as fit the column width.
            readonly property int label_step: [3, 4, 6, 8, 12].find(n => n * trend.col_w >= 44) || 12

            Canvas {
                id: canvas
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: Math.max(0, trend.ring_top - 4)
                onPaint: root.paint_trace(getContext("2d"), width, height)
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                Connections {
                    target: root
                    function onSliceChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: Style
                    function onFont_familyChanged() { canvas.requestPaint(); }
                    function onPalChanged() { canvas.requestPaint(); }
                    function onText_strongChanged() { canvas.requestPaint(); }
                    function onFrame_colorChanged() { canvas.requestPaint(); }
                    function onHairline_dimChanged() { canvas.requestPaint(); }
                }

                Rectangle {
                    visible: !!root.cursor_row
                    x: (root.cursor_index + 0.5) * trend.col_w - 0.5
                    width: 1
                    height: parent.height
                    color: Style.hairline_dim
                }

                Rectangle {
                    visible: !!root.cursor_row
                    width: 14
                    height: 14
                    radius: 7
                    x: (root.cursor_index + 0.5) * trend.col_w - width / 2
                    y: root.cursor_row ? root.trace_y(root.cursor_row.aqi, canvas.height) - height / 2 : 0
                    color: "transparent"
                    border.width: 1
                    border.color: root.ink
                }
            }

            Repeater {
                model: root.slice

                Item {
                    id: hour_col
                    required property var modelData
                    required property int index
                    readonly property bool selected: hour_col.index === root.cursor_index
                    readonly property color tone: WeatherState.aqi_color(hour_col.modelData.aqi)
                    readonly property real r: root.mini_size / 2 - 1.5

                    x: hour_col.index * trend.col_w
                    y: trend.ring_top
                    width: trend.col_w
                    height: root.reticle_size
                    opacity: hour_col.selected ? 1 : 0.8

                    Shape {
                        x: (parent.width - root.mini_size) / 2
                        y: (root.reticle_size - root.mini_size) / 2
                        width: root.mini_size
                        height: root.mini_size
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: 1
                            strokeColor: Qt.alpha(hour_col.tone, 0.3)
                            fillColor: "transparent"
                            PathAngleArc { centerX: root.mini_size / 2; centerY: root.mini_size / 2; radiusX: hour_col.r; radiusY: hour_col.r; startAngle: 0; sweepAngle: 360 }
                        }

                        ShapePath {
                            strokeWidth: 2
                            strokeColor: hour_col.tone
                            fillColor: "transparent"
                            capStyle: ShapePath.FlatCap
                            PathAngleArc { centerX: root.mini_size / 2; centerY: root.mini_size / 2; radiusX: hour_col.r; radiusY: hour_col.r; startAngle: -90; sweepAngle: 360 * Math.max(0.04, root.aqi_fraction(hour_col.modelData.aqi)) }
                        }
                    }

                    Reticle {
                        visible: hour_col.selected
                        x: (parent.width - width) / 2
                        width: root.reticle_size
                        height: root.reticle_size
                        color: Style.hairline
                    }
                }
            }

            Item {
                id: label_row
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Style.fs(-4) + 4

                Repeater {
                    model: root.slice

                    Text {
                        id: hour_label
                        required property var modelData
                        required property int index
                        readonly property bool selected: hour_label.index === root.cursor_index

                        visible: hour_label.selected || (hour_label.index % trend.label_step === 0 && Math.abs(hour_label.index - root.cursor_index) * trend.col_w >= 40)
                        x: Math.max(0, Math.min(trend.width - width, (hour_label.index + 0.5) * trend.col_w - width / 2))
                        text: WeatherState.format_hour(new Date(hour_label.modelData.dt))
                        color: hour_label.selected ? Style.text_strong : Style.text_muted
                        font.family: Style.number_font
                        font.pixelSize: Style.fs(-4)
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: mouse => {
                    if (root.slice.length === 0) return;
                    root.on_select(Math.max(0, Math.min(root.slice.length - 1, Math.floor(mouse.x / trend.col_w))));
                }
            }
        }
    }
}
