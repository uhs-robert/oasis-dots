pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.theme
import qs.services

// The targeting computer's atmosphere sensor: the current US AQI as a reading on a tick scale, the pollutants as sensor channels,
// and the 24 hours as a trace on the range grid with the cursor hour held in lock brackets. A red warning replaces the calm header when the air is unhealthy.
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property color vec: Style.text_primary
    readonly property color vec_dim: Style.text_muted
    readonly property color lock: Style.selection_brackets.a > 0 ? Style.selection_brackets : Theme.theme_label
    readonly property color alarm: Style.pal.error

    readonly property var slice: WeatherState.aq_hours.slice(0, 24)
    // The cursor is shared with the longer hourly range, so it is clamped to these 24 hours.
    readonly property int cursor_index: Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))
    readonly property var cursor_row: root.slice[root.cursor_index]
    readonly property var current: WeatherState.aq_current
    readonly property bool has_reading: WeatherState.aq_has_data && !!root.current

    // The first band the shared AQI table calls unhealthy for everyone, one step past "for sensitive groups".
    readonly property int toxic_from: 151
    readonly property bool toxic: root.has_reading && root.current.aqi >= root.toxic_from
    readonly property int scale_max: 300
    readonly property var scale_marks: [0, 50, 100, 150, 200, 300]
    // Full-scale readings per channel (ug/m3), where the gauge reads as hazardous.
    readonly property var channels: [
        { name: "PM2.5", key: "pm25", full: 150 },
        { name: "PM10", key: "pm10", full: 300 },
        { name: "OZONE", key: "ozone", full: 240 }
    ]

    readonly property int top_pad: 24
    readonly property int bottom_pad: 18

    function y_of(aqi, h, max_v) {
        const plot_h = h - root.top_pad - root.bottom_pad;
        return root.top_pad + plot_h - Math.min(1, aqi / max_v) * plot_h;
    }

    function max_value() {
        return Math.max(100, ...root.slice.map(r => r.aqi));
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const rows = root.slice;
        if (rows.length === 0) return;

        const col_w = w / rows.length;
        const max_v = root.max_value();
        const plot_h = h - root.top_pad - root.bottom_pad;
        const x_of = i => (i + 0.5) * col_w;
        const y_of = v => root.y_of(v, h, max_v);

        ctx.lineWidth = 1;
        ctx.strokeStyle = root.vec;
        for (let i = 0; i <= rows.length; i++) {
            const x = Math.round(i * col_w) + 0.5;
            ctx.globalAlpha = i < rows.length && i % 6 === 0 ? 0.2 : 0.06;
            ctx.beginPath();
            ctx.moveTo(x, root.top_pad - 6);
            ctx.lineTo(x, h - root.bottom_pad + 4);
            ctx.stroke();
        }

        // Ruler along the top, as the Hourly range chart has it.
        ctx.globalAlpha = 0.7;
        for (let i = 0; i <= rows.length * 2; i++) {
            const x = Math.round(i * col_w / 2) + 0.5;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, i % 12 === 0 ? 8 : i % 2 === 0 ? 5 : 3);
            ctx.stroke();
        }
        ctx.globalAlpha = 1;
        ctx.fillStyle = root.vec_dim;
        ctx.font = Style.fs(-5) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "left";
        for (let i = 0; i < rows.length; i += 6) ctx.fillText("+" + i, Math.round(i * col_w) + 3, 17);

        // Band edges as dashed range lines; the unhealthy edge is drawn in the alarm colour.
        ctx.setLineDash([4, 3]);
        for (const edge of [50, 100, 150]) {
            if (edge >= max_v) continue;
            const y = Math.round(y_of(edge)) + 0.5;
            const alarming = edge >= root.toxic_from - 1;
            ctx.strokeStyle = alarming ? root.alarm : root.vec;
            ctx.globalAlpha = alarming ? 0.5 : 0.22;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(w, y);
            ctx.stroke();
        }
        ctx.setLineDash([]);
        ctx.globalAlpha = 1;
        ctx.fillStyle = root.vec_dim;
        ctx.textAlign = "right";
        for (const edge of [50, 100, 150]) {
            if (edge < max_v) ctx.fillText(String(edge), w - 2, y_of(edge) - 2);
        }

        ctx.strokeStyle = root.vec;
        ctx.lineJoin = "round";
        ctx.lineWidth = 1.6;
        ctx.beginPath();
        for (let i = 0; i < rows.length; i++) {
            if (i === 0) ctx.moveTo(x_of(i), y_of(rows[i].aqi)); else ctx.lineTo(x_of(i), y_of(rows[i].aqi));
        }
        ctx.stroke();

        // A drop line from each reading to the baseline reads as the sensor's sample at that hour.
        ctx.lineWidth = 1;
        ctx.globalAlpha = 0.18;
        for (let i = 0; i < rows.length; i++) {
            ctx.beginPath();
            ctx.moveTo(x_of(i), y_of(rows[i].aqi));
            ctx.lineTo(x_of(i), root.top_pad + plot_h);
            ctx.stroke();
        }
        ctx.globalAlpha = 1;
        for (let i = 0; i < rows.length; i++) {
            ctx.fillStyle = rows[i].aqi >= root.toxic_from ? root.alarm : root.vec;
            ctx.fillRect(x_of(i) - 1.5, y_of(rows[i].aqi) - 1.5, 3, 3);
        }

        ctx.font = Style.fs(-4) + "px \"" + Style.number_font + "\"";
        ctx.textAlign = "center";
        const label_w = ctx.measureText(WeatherState.format_hour(new Date(2000, 0, 1, 12))).width + 8;
        const step = [3, 4, 6, 8, 12].find(n => n * col_w >= label_w) || 12;
        for (let i = 0; i < rows.length; i++) {
            const near_cursor = Math.abs(i - root.cursor_index) * col_w < label_w;
            if (i !== root.cursor_index && (i % step !== 0 || near_cursor)) continue;
            ctx.fillStyle = i === root.cursor_index ? root.lock : root.vec_dim;
            ctx.fillText(WeatherState.format_hour(new Date(rows[i].dt)), x_of(i), h - 4);
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !WeatherState.aq_has_data
        text: WeatherState.aq_loading ? "SCANNING…" : "ATMOSPHERE SENSOR OFFLINE"
        color: Style.text_dim
        font.family: Style.font_family
        font.pixelSize: Style.font_size
        font.letterSpacing: 2
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6
        visible: root.has_reading

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: root.current ? root.current.aqi : "--"
                color: Style.text_strong
                font.family: Style.number_font
                font.pixelSize: Style.fs(14)
                font.bold: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0

                Text {
                    text: "ATMOSPHERE · US AQI"
                    color: root.vec_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                    font.bold: true
                    font.letterSpacing: 1.5
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.current ? WeatherState.aqi_band(root.current.aqi).label.toUpperCase() : ""
                    color: root.current ? WeatherState.aqi_color(root.current.aqi) : root.vec
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(0)
                    font.bold: true
                    font.letterSpacing: 1
                }
            }

            Rectangle {
                visible: root.toxic
                implicitWidth: toxic_text.implicitWidth + 14
                implicitHeight: toxic_text.implicitHeight + 8
                color: Qt.alpha(root.alarm, 0.16)
                border.width: 1
                border.color: root.alarm

                Text {
                    id: toxic_text
                    anchors.centerIn: parent
                    text: "ATMOSPHERE\nTOXIC"
                    horizontalAlignment: Text.AlignHCenter
                    color: root.alarm
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                    font.bold: true
                    font.letterSpacing: 1.5
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: aqi_gauge.implicitHeight + scale_labels.height + 2

            TickGauge {
                id: aqi_gauge
                width: parent.width
                height: 12
                value: root.current ? root.current.aqi / root.scale_max : 0
                color: root.toxic ? root.alarm : root.vec
                marked: true
                mark_color: root.lock
            }

            Item {
                id: scale_labels
                y: aqi_gauge.height + 2
                width: parent.width
                height: Math.round(Style.fs(-5) + 2)

                Repeater {
                    model: root.scale_marks

                    Text {
                        id: scale_mark
                        required property int modelData
                        readonly property real along: Math.round(scale_mark.modelData / root.scale_max * (aqi_gauge.tick_count - 1)) * aqi_gauge.pitch
                        x: Math.max(0, Math.min(scale_labels.width - width, scale_mark.along - width / 2))
                        text: String(scale_mark.modelData)
                        color: root.vec_dim
                        font.family: Style.number_font
                        font.pixelSize: Style.fs(-5)
                    }
                }
            }
        }

        Repeater {
            model: root.channels

            RowLayout {
                id: channel
                required property var modelData
                readonly property var reading: root.current ? root.current[channel.modelData.key] : null
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.preferredWidth: Math.round(Style.fs(-3) * 4.6)
                    text: channel.modelData.name
                    color: root.vec_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                    font.bold: true
                    font.letterSpacing: 1
                }

                TickGauge {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 9
                    value: channel.reading !== null ? channel.reading / channel.modelData.full : 0
                    color: root.vec
                }

                Text {
                    Layout.preferredWidth: Math.round(Style.fs(-1) * 4)
                    horizontalAlignment: Text.AlignRight
                    text: channel.reading !== null ? channel.reading.toFixed(1) : "--"
                    color: Style.text_strong
                    font.family: Style.number_font
                    font.pixelSize: Style.fs(-1)
                    font.bold: true
                }

                Text {
                    text: "µg/m³"
                    color: root.vec_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 2
            elide: Text.ElideRight
            readonly property var r: root.cursor_row
            text: r ? "RANGE " + String(root.cursor_index).padStart(2, "0") + " · " + WeatherState.format_hour(new Date(r.dt)) + " · AQI " + r.aqi + " · " + WeatherState.aqi_band(r.aqi).label.toUpperCase() : "RANGE --"
            color: root.lock
            font.family: Style.number_font
            font.pixelSize: Style.fs(-1)
            font.bold: true
            font.letterSpacing: 1
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 60
            Layout.bottomMargin: 4

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(root.vec, 0.22)
            }

            CornerBrackets {
                anchors.fill: parent
                color: root.vec
                inset: 0
                arm: 12
                thickness: 1.5
                all_corners: true
            }

            Item {
                id: plot
                anchors.fill: parent
                anchors.margins: 3

                readonly property real col_w: root.slice.length > 0 ? plot.width / root.slice.length : plot.width
                readonly property bool has_cursor: !!root.cursor_row

                Canvas {
                    id: canvas
                    anchors.fill: parent
                    onPaint: root.paint(getContext("2d"), width, height)
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    Connections {
                        target: WeatherState
                        function onAq_hoursChanged() { canvas.requestPaint(); }
                    }
                    Connections {
                        target: Style
                        function onFont_familyChanged() { canvas.requestPaint(); }
                        function onFont_sizeChanged() { canvas.requestPaint(); }
                        function onPalChanged() { canvas.requestPaint(); }
                        function onText_primaryChanged() { canvas.requestPaint(); }
                        function onText_mutedChanged() { canvas.requestPaint(); }
                        function onSelection_bracketsChanged() { canvas.requestPaint(); }
                    }
                    Connections {
                        target: TimeFormat
                        function onH24Changed() { canvas.requestPaint(); }
                    }
                    Connections {
                        target: root
                        function onCursor_indexChanged() { canvas.requestPaint(); }
                    }
                }

                Rectangle {
                    visible: plot.has_cursor
                    x: root.cursor_index * plot.col_w
                    width: plot.col_w
                    height: plot.height
                    color: Style.selection_bg
                    z: -1
                }

                Rectangle {
                    visible: plot.has_cursor
                    x: (root.cursor_index + 0.5) * plot.col_w - 0.5
                    y: root.top_pad - 6
                    width: 1
                    height: plot.height - root.top_pad + 6 - root.bottom_pad + 4
                    color: root.lock
                    opacity: 0.45
                }

                Reticle {
                    visible: plot.has_cursor
                    width: 20
                    height: 20
                    x: (root.cursor_index + 0.5) * plot.col_w - 10
                    y: (root.cursor_row ? root.y_of(root.cursor_row.aqi, plot.height, root.max_value()) : 0) - 10
                    color: root.lock
                    center_color: root.lock
                }

                // The brackets close in on the new hour whenever the cursor moves.
                Item {
                    id: lock_box
                    property real gap: 0
                    visible: plot.has_cursor
                    x: root.cursor_index * plot.col_w
                    width: plot.col_w
                    height: plot.height

                    CornerBrackets {
                        anchors.fill: parent
                        color: root.lock
                        inset: lock_box.gap
                        arm: 6
                        thickness: 1.5
                        all_corners: true
                    }

                    NumberAnimation {
                        id: close_in
                        target: lock_box
                        property: "gap"
                        from: -7
                        to: 0
                        duration: 180
                        easing.type: Easing.OutCubic
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

    onCursor_indexChanged: close_in.restart()
}
