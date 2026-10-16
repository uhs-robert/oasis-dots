import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../../components"
import "../../theme"
import "../../services"

// The HEV suit's environment scan: AQI as a hazard level in HUD numerals, each pollutant as a sensor channel with a gauge,
// a warning once the air is unhealthy, and the 24 AQI hours as a monitor trace. h/l move the hour cursor.
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property var slice: WeatherState.aq_hours.slice(0, 24)
    // The cursor is shared with the longer hourly range, so it is clamped to these 24 hours.
    readonly property int cursor_index: Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))
    readonly property var cursor_row: root.slice[root.cursor_index]

    readonly property var cur: WeatherState.aq_current
    readonly property bool ready: WeatherState.aq_has_data && !!root.cur
    readonly property int aqi: root.ready ? root.cur.aqi : -1
    readonly property var band: root.ready ? WeatherState.aqi_band(root.aqi) : null
    readonly property int level: root.ready ? WeatherState.aqi_bands.indexOf(root.band) : 0
    readonly property color band_color: root.ready ? WeatherState.aqi_color(root.aqi) : Style.text_dim
    // The suit speaks up from "unhealthy for sensitive groups", as the header voice does.
    readonly property bool hazard: root.aqi > 100
    readonly property bool wide: root.width >= 300

    readonly property color hl: Style.text_primary
    readonly property color hl_t: Style.text_muted
    readonly property color alarm: Theme.theme_label
    readonly property color phosphor: Style.pal.green
    readonly property int legend_h: 18
    readonly property int bezel: 5

    // Each gauge's full scale is twice the concentration where that pollutant first reads unhealthy for sensitive groups,
    // so the tick at mid-gauge is the suit's limit.
    readonly property var channels: [
        { name: "PM2.5", value: root.ready ? root.cur.pm25 : null, limit: 35 },
        { name: "PM10", value: root.ready ? root.cur.pm10 : null, limit: 155 },
        { name: "OZONE", value: root.ready ? root.cur.ozone : null, limit: 137 }
    ]

    Text {
        anchors.centerIn: parent
        visible: !root.ready
        text: WeatherState.aq_loading ? "SENSORS INITIALIZING" : "AIR QUALITY SENSORS OFFLINE"
        color: WeatherState.aq_loading ? root.hl_t : root.alarm
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.bold: true
        font.letterSpacing: 2
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6
        visible: root.ready

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: root.hazard ? "HAZARDOUS ENVIRONMENT" : "ENVIRONMENT SCAN"
                color: root.hazard ? root.alarm : root.hl
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
                font.bold: true
                font.letterSpacing: 3.2
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Style.hairline_dim
            }

            Text {
                text: "LEVEL " + (root.level + 1) + " / " + WeatherState.aqi_bands.length
                color: root.hl_t
                font.family: Style.number_font
                font.pixelSize: Style.fs(-6)
                font.bold: true
                font.letterSpacing: 1.5
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: root.wide ? 14 : 10

            Row {
                spacing: 3
                Layout.alignment: Qt.AlignBottom

                Text {
                    text: root.aqi
                    color: root.hl
                    font.family: Style.number_font
                    font.pixelSize: root.wide ? 46 : 36
                    font.bold: true
                    lineHeight: 0.9
                }

                Text {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    text: "AQI"
                    color: root.hl_t
                    font.family: Style.number_font
                    font.pixelSize: Style.fs(-3)
                    font.bold: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignBottom
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.band ? root.band.label.toUpperCase() : ""
                    color: root.band_color
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                    font.bold: true
                    font.letterSpacing: 1.5
                }

                SkewBar {
                    Layout.fillWidth: true
                    Layout.leftMargin: 5
                    cells: WeatherState.aqi_bands.length
                    value: (root.level + 1) / WeatherState.aqi_bands.length
                    on_color: root.band_color
                }
            }
        }

        Rectangle {
            visible: root.hazard
            Layout.fillWidth: true
            Layout.preferredHeight: warning_row.implicitHeight + 8
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.alpha(root.alarm, 0.16) }
                GradientStop { position: 1; color: "transparent" }
            }

            Rectangle {
                width: 2
                height: parent.height
                color: root.alarm
            }

            RowLayout {
                id: warning_row
                x: 8
                width: parent.width - 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Item {
                    Layout.preferredWidth: 13
                    Layout.preferredHeight: 12
                    Layout.alignment: Qt.AlignVCenter

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: -1
                            fillColor: root.alarm
                            PathPolyline { path: [Qt.point(6.5, 0), Qt.point(13, 12), Qt.point(0, 12), Qt.point(6.5, 0)] }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -1
                        text: "!"
                        color: Theme.bg_crust
                        font.family: Style.number_font
                        font.pixelSize: 9
                        font.bold: true
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: "WARNING: AIR QUALITY HAZARD"
                    color: root.alarm
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                    font.bold: true
                    font.letterSpacing: 1.3
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: root.wide ? 14 : 10

            Repeater {
                model: root.channels

                RowLayout {
                    id: channel
                    required property var modelData
                    required property int index
                    readonly property bool over: channel.modelData.value !== null && channel.modelData.value > channel.modelData.limit
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    spacing: root.wide ? 14 : 10

                    // The first channel keeps a blank divider so all three columns are the same width.
                    Rectangle {
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        color: channel.index > 0 ? Style.hairline : "transparent"
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 3

                        Row {
                            spacing: 3

                            Text {
                                text: channel.modelData.value !== null ? channel.modelData.value.toFixed(1) : "--"
                                color: channel.over ? root.alarm : root.hl
                                font.family: Style.number_font
                                font.pixelSize: root.wide ? 24 : 20
                                font.bold: true
                                lineHeight: 0.9
                            }

                            Text {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 2
                                text: "µg/m³"
                                color: root.hl_t
                                font.family: Style.number_font
                                font.pixelSize: Style.fs(-6)
                                font.bold: true
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: gauge.implicitHeight

                            SkewBar {
                                id: gauge
                                anchors.fill: parent
                                anchors.leftMargin: 5
                                cells: 8
                                value: channel.modelData.value !== null ? channel.modelData.value / (channel.modelData.limit * 2) : 0
                                on_color: channel.over ? root.alarm : root.hl
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: "CH" + (channel.index + 1) + " " + channel.modelData.name
                            color: root.hl_t
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-6)
                            font.bold: true
                            font.letterSpacing: 2.2
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 8

            Text {
                text: root.cursor_row ? WeatherState.format_hour(new Date(root.cursor_row.dt)) : "--"
                color: root.hl
                font.family: Style.number_font
                font.pixelSize: Style.fs(6)
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.cursor_row ? WeatherState.aqi_band(root.cursor_row.aqi).label : ""
                color: root.hl_t
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }

            Text {
                visible: !!root.cursor_row
                text: root.cursor_row ? "AQI " + root.cursor_row.aqi : ""
                color: root.cursor_row ? WeatherState.aqi_color(root.cursor_row.aqi) : root.hl
                font.family: Style.number_font
                font.pixelSize: Style.fs(6)
                font.bold: true
            }
        }

        // The monitor: a bezel around the legend strip and the AQI trace with its hour labels.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 60
            color: Theme.bg_crust
            border.width: 1
            border.color: Style.hairline

            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                color: "transparent"
                border.width: 1
                border.color: Style.hairline_dim
            }

            Item {
                anchors.fill: parent
                anchors.margins: root.bezel

                RowLayout {
                    id: legend
                    width: parent.width
                    height: root.legend_h
                    spacing: 6

                    Rectangle {
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        color: root.phosphor
                    }

                    Text {
                        text: "CH1 US AQI"
                        color: root.hl
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                        font.bold: true
                        font.letterSpacing: 2
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "- - 100 LIMIT"
                        color: root.hl_t
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                        font.bold: true
                        font.letterSpacing: 1.5
                    }
                }

                Canvas {
                    id: canvas
                    y: root.legend_h
                    width: parent.width
                    height: parent.height - root.legend_h

                    readonly property var rows: root.slice
                    readonly property real col_w: canvas.rows.length > 0 ? canvas.width / canvas.rows.length : canvas.width

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const w = width, h = height;
                        const rows = canvas.rows;
                        if (rows.length === 0) return;

                        const top_pad = 14;
                        const label_h = 16;
                        const chart_h = h - top_pad - label_h;
                        const max_v = Math.max(100, ...rows.map(r => r.aqi)) * 1.1;
                        const col_w = canvas.col_w;
                        const y_of = v => top_pad + chart_h - Math.min(1, v / max_v) * chart_h;

                        ctx.lineWidth = 1;
                        ctx.strokeStyle = root.hl;
                        for (let i = 0; i <= rows.length; i++) {
                            const x = Math.round(i * col_w) + 0.5;
                            ctx.globalAlpha = i < rows.length && new Date(rows[i].dt).getHours() % 6 === 0 ? 0.2 : 0.08;
                            ctx.beginPath();
                            ctx.moveTo(x, 0);
                            ctx.lineTo(x, top_pad + chart_h + 4);
                            ctx.stroke();
                        }
                        for (let d = 0; d <= 4; d++) {
                            const y = Math.round(top_pad + chart_h * d / 4) + 0.5;
                            ctx.globalAlpha = d === 4 ? 0.28 : 0.1;
                            ctx.beginPath();
                            ctx.moveTo(0, y);
                            ctx.lineTo(w, y);
                            ctx.stroke();
                        }

                        if (root.cursor_row) {
                            ctx.globalAlpha = 1;
                            ctx.fillStyle = Style.selection_bg;
                            ctx.fillRect(root.cursor_index * col_w, 0, col_w, top_pad + chart_h + label_h);
                            ctx.strokeStyle = Style.selection_border;
                            ctx.strokeRect(root.cursor_index * col_w + 0.5, 0.5, col_w - 1, top_pad + chart_h + label_h - 1);
                        }

                        for (let i = 0; i < rows.length; i++) {
                            const bar_w = Math.max(3, col_w * 0.56);
                            const y = y_of(rows[i].aqi);
                            ctx.fillStyle = WeatherState.aqi_color(rows[i].aqi);
                            ctx.globalAlpha = i === root.cursor_index ? 0.9 : 0.5;
                            ctx.fillRect(i * col_w + (col_w - bar_w) / 2, y, bar_w, top_pad + chart_h - y);
                        }

                        // The 100 line is where the scale leaves "good" and "moderate".
                        ctx.setLineDash([4, 3]);
                        ctx.strokeStyle = root.hl;
                        ctx.globalAlpha = 0.6;
                        ctx.beginPath();
                        ctx.moveTo(0, Math.round(y_of(100)) + 0.5);
                        ctx.lineTo(w, Math.round(y_of(100)) + 0.5);
                        ctx.stroke();
                        ctx.setLineDash([]);

                        ctx.strokeStyle = root.phosphor;
                        ctx.lineJoin = "round";
                        for (const pass of [[6, 0.12], [3.5, 0.25], [1.5, 1]]) {
                            ctx.lineWidth = pass[0];
                            ctx.globalAlpha = pass[1];
                            ctx.beginPath();
                            for (let i = 0; i < rows.length; i++) {
                                const x = (i + 0.5) * col_w;
                                if (i === 0) ctx.moveTo(x, y_of(rows[i].aqi)); else ctx.lineTo(x, y_of(rows[i].aqi));
                            }
                            ctx.stroke();
                        }
                        ctx.globalAlpha = 1;
                        ctx.fillStyle = root.phosphor;
                        for (let i = 0; i < rows.length; i++) ctx.fillRect((i + 0.5) * col_w - 1.5, y_of(rows[i].aqi) - 1.5, 3, 3);

                        const cursor_x = (root.cursor_index + 0.5) * col_w;
                        ctx.fillStyle = root.hl;
                        ctx.font = "bold " + Style.fs(-3) + "px \"" + Style.number_font + "\"";
                        ctx.textAlign = "center";
                        ctx.fillText(String(root.cursor_row.aqi), Math.max(14, Math.min(w - 14, cursor_x)), Math.max(10, y_of(root.cursor_row.aqi) - 6));

                        ctx.font = Style.fs(-4) + "px \"" + Style.number_font + "\"";
                        const label_w = ctx.measureText(WeatherState.format_hour(new Date(2000, 0, 1, 12))).width + 8;
                        const step = [3, 4, 6, 8, 12].find(n => n * col_w >= label_w) || 12;
                        for (let i = 0; i < rows.length; i++) {
                            const selected = i === root.cursor_index;
                            if (!selected && (i % step !== 0 || Math.abs(i - root.cursor_index) * col_w < label_w)) continue;
                            ctx.fillStyle = selected ? root.hl : root.hl_t;
                            ctx.fillText(WeatherState.format_hour(new Date(rows[i].dt)), Math.max(label_w / 2, Math.min(w - label_w / 2, (i + 0.5) * col_w)), h - 4);
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
                    Connections {
                        target: root
                        function onCursor_indexChanged() { canvas.requestPaint(); }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: mouse => {
                            if (canvas.rows.length === 0) return;
                            root.on_select(Math.max(0, Math.min(canvas.rows.length - 1, Math.floor(mouse.x / canvas.col_w))));
                        }
                    }
                }
            }
        }
    }
}
