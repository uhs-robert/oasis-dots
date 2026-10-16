import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services

// WeatherStar 4000 "Air Quality": the US AQI in the big lettering over a pollutant table, then the next 24 hours as bars in the Hourly Graph's style.
// h/l move the hour cursor.
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

    readonly property var rows: !root.ready ? [] : [
        ["PM2.5:", root.cur.pm25],
        ["PM10:", root.cur.pm10],
        ["Ozone:", root.cur.ozone]
    ]

    readonly property int axis_w: Style.px(28)
    readonly property int plot_top: 6
    readonly property int label_h: Style.fs(-4) + 6
    readonly property real max_v: Math.max(100, ...root.slice.map(r => r.aqi))
    // Grid every 50 up to the data, widening the step when the scale gets tall.
    readonly property int grid_step: root.max_v > 300 ? 100 : 50

    component Label: Text {
        color: Theme.fg_strong
        font.family: Style.font_family
        font.pixelSize: Style.fs(-3)
        style: Text.Outline
        styleColor: Theme.bg_shadow
    }

    Label {
        anchors.centerIn: parent
        visible: !root.ready
        text: WeatherState.aq_loading ? "Loading…" : "Air quality unavailable"
        font.pixelSize: Style.font_size
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4
        visible: root.ready

        Label {
            text: "Air Quality"
            color: Theme.theme_secondary
            font.pixelSize: Style.fs(-1)
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: summary.implicitHeight + 16

            WsPanel {
                anchors.fill: parent
            }

            RowLayout {
                id: summary
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 12

                ColumnLayout {
                    Layout.preferredWidth: Math.max(Style.px(110), parent.width * 0.4)
                    Layout.alignment: Qt.AlignTop
                    spacing: 0

                    Label {
                        text: root.cur ? root.cur.aqi : "--"
                        color: root.cur ? WeatherState.aqi_color(root.cur.aqi) : Style.text_dim
                        font.pixelSize: Style.fs(26)
                        font.bold: true
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: root.cur ? WeatherState.aqi_band(root.cur.aqi).label : ""
                        color: root.cur ? WeatherState.aqi_color(root.cur.aqi) : Style.text_dim
                        font.pixelSize: Style.fs(-2)
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 2

                    Repeater {
                        model: root.rows

                        Repeater {
                            id: reading
                            required property var modelData
                            model: 2

                            Label {
                                required property int index
                                Layout.fillWidth: index === 0
                                horizontalAlignment: index === 0 ? Text.AlignLeft : Text.AlignRight
                                text: index === 0 ? reading.modelData[0] : (reading.modelData[1] !== null ? reading.modelData[1].toFixed(1) : "--")
                                color: index === 0 ? Theme.theme_primary_light : Theme.fg_strong
                                font.pixelSize: Style.fs(-2)
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "24 Hour Trend"
                color: Theme.theme_secondary
                font.pixelSize: Style.fs(-1)
            }

            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: root.cursor_row ? WeatherState.format_hour(new Date(root.cursor_row.dt)) + " · AQI " + root.cursor_row.aqi + " " + WeatherState.aqi_band(root.cursor_row.aqi).label : ""
                color: root.cursor_row ? WeatherState.aqi_color(root.cursor_row.aqi) : Theme.fg_strong
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            WsPanel {
                anchors.fill: parent
            }

            Canvas {
                id: canvas
                anchors.fill: parent
                anchors.margins: 4

                readonly property real chart_h: Math.max(1, height - root.plot_top - root.label_h)
                readonly property real chart_w: Math.max(1, width - root.axis_w)
                readonly property real col_w: chart_w / Math.max(1, root.slice.length)

                function y_of(v) {
                    return root.plot_top + canvas.chart_h - Math.min(1, v / root.max_v) * canvas.chart_h;
                }

                function shadowed_text(ctx, text, x, y, color) {
                    ctx.fillStyle = Theme.bg_shadow;
                    ctx.fillText(text, x + 1, y + 1);
                    ctx.fillStyle = color;
                    ctx.fillText(text, x, y);
                }

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const rows = root.slice;
                    if (rows.length === 0) return;
                    const col_w = canvas.col_w;
                    const x0 = root.axis_w;

                    ctx.font = Style.fs(-4) + "px \"" + Style.font_family + "\"";
                    ctx.lineWidth = 1;
                    ctx.textAlign = "right";
                    for (let v = 0; v <= root.max_v; v += root.grid_step) {
                        const y = Math.round(canvas.y_of(v)) + 0.5;
                        ctx.globalAlpha = 0.45;
                        ctx.strokeStyle = Theme.theme_primary_light;
                        ctx.beginPath();
                        ctx.moveTo(x0, y);
                        ctx.lineTo(canvas.width, y);
                        ctx.stroke();
                        ctx.globalAlpha = 1;
                        canvas.shadowed_text(ctx, "" + v, x0 - 4, y + 3, Theme.fg_strong);
                    }

                    ctx.fillStyle = Qt.alpha(Theme.theme_secondary, 0.14);
                    ctx.fillRect(x0 + root.cursor_index * col_w, 0, col_w, canvas.chart_h + root.plot_top);
                    ctx.strokeStyle = Theme.theme_secondary;
                    ctx.lineWidth = 2;
                    ctx.strokeRect(x0 + root.cursor_index * col_w + 1, 1, col_w - 2, canvas.chart_h + root.plot_top - 2);

                    const label_w = ctx.measureText(WeatherState.format_hour(new Date(2000, 0, 1, 12))).width + 8;
                    const step = [2, 3, 4, 6, 8, 12].find(n => n * col_w >= label_w) || 12;
                    const base_y = root.plot_top + canvas.chart_h;
                    const bar_w = Math.max(3, col_w * 0.62);
                    ctx.textAlign = "center";
                    for (let i = 0; i < rows.length; i++) {
                        const x = x0 + i * col_w + (col_w - bar_w) / 2;
                        const y = canvas.y_of(rows[i].aqi);
                        ctx.fillStyle = Theme.bg_shadow;
                        ctx.fillRect(x - 1, y - 1, bar_w + 2, base_y - y + 1);
                        ctx.fillStyle = WeatherState.aqi_color(rows[i].aqi);
                        ctx.fillRect(x, y, bar_w, base_y - y);
                        if (i % step === 0) {
                            const is_cursor = i === root.cursor_index;
                            canvas.shadowed_text(ctx, WeatherState.format_hour(new Date(rows[i].dt)), x0 + i * col_w + col_w / 2, canvas.height - 4, is_cursor ? Theme.theme_secondary : Theme.fg_strong);
                        }
                    }
                }

                Connections {
                    target: WeatherState
                    function onAq_hoursChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: root
                    function onCursor_indexChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: TimeFormat
                    function onH24Changed() { canvas.requestPaint(); }
                }
                Connections {
                    target: Style
                    function onFont_familyChanged() { canvas.requestPaint(); }
                    function onFont_sizeChanged() { canvas.requestPaint(); }
                    function onPalChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: Theme
                    function onFg_strongChanged() { canvas.requestPaint(); }
                    function onBg_shadowChanged() { canvas.requestPaint(); }
                    function onTheme_secondaryChanged() { canvas.requestPaint(); }
                    function onTheme_primary_lightChanged() { canvas.requestPaint(); }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mouse => {
                        if (root.slice.length === 0) return;
                        const idx = Math.floor((mouse.x - root.axis_w) / canvas.col_w);
                        if (idx >= 0 && idx < root.slice.length) root.on_select(idx);
                    }
                }
            }
        }
    }
}
