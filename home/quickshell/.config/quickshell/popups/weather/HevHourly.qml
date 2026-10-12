// home/quickshell/.config/quickshell/popups/weather/HevHourly.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// A Black Mesa lab oscilloscope: the hours as a scrolling phosphor trace on a graticule inside a monitor bezel, HEV amber numerals.
// sub: 0 temp, 1 precip (chance + amount), 2 wind, 3 UV, 4 humidity. h/l move the hour cursor (auto-scrolling into view).
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    readonly property var channel_names: ["TEMP", "PRECIP", "WIND", "UV", "HUMID"]

    readonly property int hour_col_w: 56
    readonly property int icon_row_h: 28
    readonly property int label_row_h: 18
    readonly property int legend_h: 18
    readonly property int bezel: 5
    readonly property color hl: Style.text_primary
    readonly property color hl_t: Style.text_muted
    readonly property color phosphor: Style.pal.green
    readonly property color rain: Theme.info
    readonly property real readout_h: Math.max(26, readout_row.implicitHeight)
    readonly property int chart_h: root.height - root.readout_h - 6 - 2 * root.bezel - root.legend_h - root.icon_row_h - root.label_row_h - 4

    readonly property var day_boundaries: {
        const list = [];
        let last_date = null;
        const today_str = WeatherState.location_date_str();
        const hrs = WeatherState.hours;
        for (let i = 0; i < hrs.length; i++) {
            if (hrs[i].date !== last_date) {
                const label = hrs[i].date === today_str ? "TODAY" : Qt.formatDate(new Date(hrs[i].date + "T00:00:00"), "ddd").toUpperCase();
                list.push({ index: i, label: label });
                last_date = hrs[i].date;
            }
        }
        return list;
    }

    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]

    // Heavy rain in the forecast's own unit, so amount bars read the same in mm and inches.
    readonly property real precip_full_scale: WeatherState.metric ? 5 : 0.2

    function value_of(row) {
        return [row.temp, row.pop, row.wind_speed, row.uv_index, row.humidity][root.sub];
    }

    function value_text(v) {
        if (root.sub === 3) return v.toFixed(1);
        return Math.round(v) + (root.sub === 1 || root.sub === 4 ? "%" : root.sub === 0 ? "°" : "");
    }

    function unit_text() {
        return ["°" + WeatherState.unit_symbol(), "% CHANCE", WeatherState.wind_unit(), "UV INDEX", "% RH"][root.sub];
    }

    function secondary_name() {
        return root.sub === 0 ? "FEELS" : root.sub === 2 ? "GUSTS" : "";
    }

    function scroll_to_cursor() {
        const cursor_x = root.hour_cursor * root.hour_col_w;
        // Narrow views get a smaller lead so the two margins never overlap.
        const margin = Math.max(0, Math.min(root.hour_col_w * 2, (flick.width - root.hour_col_w) / 2));
        if (cursor_x < flick.contentX + margin) {
            flick.contentX = Math.max(0, cursor_x - margin);
        } else if (cursor_x + root.hour_col_w > flick.contentX + flick.width - margin) {
            flick.contentX = Math.min(Math.max(0, flick.contentWidth - flick.width), cursor_x + root.hour_col_w - flick.width + margin);
        }
    }

    property bool want_scroll: false

    function request_scroll() {
        if (flick.width > 0) root.scroll_to_cursor();
        else root.want_scroll = true;
    }

    function secondary_of(hrs) {
        return root.sub === 0 ? hrs.map(r => r.feels) : root.sub === 2 ? hrs.map(r => r.wind_gusts) : null;
    }

    // The dashed trace shares the scale, so gusts above the speeds stay on screen.
    function scale_range(hrs) {
        const values = hrs.map(root.value_of).concat(root.secondary_of(hrs) || []);
        if (root.sub === 1 || root.sub === 4) return { lo: 0, hi: 100 };
        if (root.sub === 3) return { lo: 0, hi: Math.max(12, Math.max(...values) + 1) };
        let lo = Math.min(...values);
        let hi = Math.max(...values);
        const pad = Math.max(2, (hi - lo) * 0.15);
        return { lo: lo - pad, hi: hi + pad };
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return;

        const values = hrs.map(root.value_of);
        const range = root.scale_range(hrs);
        const top_pad = 20;
        const amount_px = Style.fs(-3);
        const bottom_pad = root.sub === 1 ? amount_px + 8 : 4;
        const plot_h = h - top_pad - bottom_pad;
        const y_of = v => top_pad + plot_h - ((v - range.lo) / (range.hi - range.lo || 1)) * plot_h;
        const x_of = i => i * root.hour_col_w + root.hour_col_w / 2;

        // Graticule: hour columns, a heavier line every six hours, four horizontal divisions with tick marks on the centre line.
        ctx.lineWidth = 1;
        ctx.strokeStyle = root.hl;
        for (let i = 0; i <= hrs.length; i++) {
            const x = Math.round(i * root.hour_col_w) + 0.5;
            ctx.globalAlpha = i < hrs.length && hrs[i].hour % 6 === 0 ? 0.2 : 0.08;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
        }
        for (let d = 0; d <= 4; d++) {
            const y = Math.round(top_pad + plot_h * d / 4) + 0.5;
            ctx.globalAlpha = d === 2 ? 0.28 : 0.1;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(w, y);
            ctx.stroke();
        }
        ctx.globalAlpha = 0.28;
        const mid_y = Math.round(top_pad + plot_h / 2);
        for (let i = 0; i < hrs.length * 4; i++) {
            const x = Math.round(i * root.hour_col_w / 4) + 0.5;
            ctx.beginPath();
            ctx.moveTo(x, mid_y - (i % 4 === 0 ? 4 : 2));
            ctx.lineTo(x, mid_y + (i % 4 === 0 ? 5 : 3));
            ctx.stroke();
        }

        ctx.globalAlpha = 0.6;
        for (const b of root.day_boundaries) {
            const x = Math.round(b.index * root.hour_col_w) + 0.5;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
        }
        ctx.globalAlpha = 1;
        ctx.fillStyle = root.hl_t;
        ctx.font = "bold " + Style.fs(-5) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "left";
        for (const b of root.day_boundaries) ctx.fillText(b.label, b.index * root.hour_col_w + 4, 12);

        if (root.sub === 1) {
            ctx.fillStyle = root.rain;
            for (let i = 0; i < hrs.length; i++) {
                if (hrs[i].precip <= 0) continue;
                const bar_h = Math.max(1, Math.min(1, hrs[i].precip / root.precip_full_scale) * 14);
                ctx.globalAlpha = 0.55;
                ctx.fillRect(x_of(i) - 8, h - bottom_pad - bar_h, 16, bar_h);
            }
            ctx.globalAlpha = 0.14;
            ctx.beginPath();
            ctx.moveTo(x_of(0), h - bottom_pad);
            for (let i = 0; i < hrs.length; i++) ctx.lineTo(x_of(i), y_of(hrs[i].pop));
            ctx.lineTo(x_of(hrs.length - 1), h - bottom_pad);
            ctx.closePath();
            ctx.fillStyle = root.phosphor;
            ctx.fill();
            ctx.globalAlpha = 1;
        }

        // Dashed second trace: feels-like for temp, gusts for wind.
        const secondary = root.secondary_of(hrs);
        if (secondary) {
            ctx.setLineDash([4, 3]);
            ctx.strokeStyle = root.hl;
            ctx.globalAlpha = 0.6;
            ctx.lineWidth = 1.2;
            ctx.beginPath();
            for (let i = 0; i < hrs.length; i++) {
                if (i === 0) ctx.moveTo(x_of(i), y_of(secondary[i])); else ctx.lineTo(x_of(i), y_of(secondary[i]));
            }
            ctx.stroke();
            ctx.setLineDash([]);
            ctx.globalAlpha = 1;
        }

        // Phosphor glow: the same path wide and faint, then narrow and bright.
        ctx.strokeStyle = root.phosphor;
        ctx.lineJoin = "round";
        for (const pass of [[7, 0.12], [4, 0.25], [1.6, 1]]) {
            ctx.lineWidth = pass[0];
            ctx.globalAlpha = pass[1];
            ctx.beginPath();
            for (let i = 0; i < hrs.length; i++) {
                if (i === 0) ctx.moveTo(x_of(i), y_of(values[i])); else ctx.lineTo(x_of(i), y_of(values[i]));
            }
            ctx.stroke();
        }
        ctx.globalAlpha = 1;

        ctx.fillStyle = root.phosphor;
        for (let i = 0; i < hrs.length; i++) ctx.fillRect(x_of(i) - 1.5, y_of(values[i]) - 1.5, 3, 3);

        ctx.fillStyle = root.hl;
        ctx.font = "bold " + Style.fs(-3) + "px \"" + Style.number_font + "\"";
        ctx.textAlign = "center";
        for (let i = 0; i < hrs.length; i++) ctx.fillText(root.value_text(values[i]), x_of(i), Math.max(12, y_of(values[i]) - 8));

        if (root.sub === 1) {
            ctx.fillStyle = root.rain;
            ctx.font = amount_px + "px \"" + Style.number_font + "\"";
            for (let i = 0; i < hrs.length; i++) ctx.fillText(hrs[i].precip.toFixed(hrs[i].precip < 1 ? 2 : 1), x_of(i), h - 3);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // Cursor readout: the hour in HUD numerals, the shared line's details, the channel's value at the cursor.
        RowLayout {
            id: readout_row
            Layout.fillWidth: true
            Layout.preferredHeight: root.readout_h
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
                text: {
                    const r = root.cursor_row;
                    if (!r) return "";
                    return [Math.round(r.temp) + "°" + WeatherState.unit_symbol(), r.pop + "% pop", r.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in"), r.cond].join(" · ");
                }
                color: root.hl_t
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }

            Text {
                visible: !!root.cursor_row && root.sub !== 0
                text: root.cursor_row ? root.value_text(root.value_of(root.cursor_row)) : ""
                color: root.phosphor
                font.family: Style.number_font
                font.pixelSize: Style.fs(6)
                font.bold: true
            }
        }

        // The monitor: a bezel around the legend strip, the scrolling screen and the hour labels beneath it.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
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
                        text: "CH1 " + root.channel_names[root.sub]
                        color: root.hl
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                        font.bold: true
                        font.letterSpacing: 2
                    }

                    Text {
                        text: root.unit_text()
                        color: root.hl_t
                        font.family: Style.number_font
                        font.pixelSize: Style.fs(-6)
                        font.bold: true
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: root.secondary_name() !== ""
                        text: "- - " + root.secondary_name()
                        color: root.hl_t
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                        font.bold: true
                        font.letterSpacing: 1.5
                    }

                    Text {
                        visible: root.sub === 1
                        text: WeatherState.metric ? "MM / HR" : "IN / HR"
                        color: root.rain
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                        font.bold: true
                        font.letterSpacing: 1.5
                    }
                }

                Flickable {
                    id: flick
                    y: root.legend_h
                    width: parent.width
                    height: parent.height - root.legend_h
                    clip: true
                    contentWidth: WeatherState.hours.length * root.hour_col_w
                    contentHeight: height
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    onContentXChanged: root.on_scroll(flick.contentX)

                    onWidthChanged: {
                        if (root.want_scroll && flick.width > 0) {
                            root.want_scroll = false;
                            root.scroll_to_cursor();
                        }
                    }

                    Component.onCompleted: flick.contentX = root.scroll_x

                    Item {
                        width: flick.contentWidth
                        height: flick.contentHeight

                        Canvas {
                            id: canvas
                            width: parent.width
                            height: root.chart_h
                            onPaint: root.paint(getContext("2d"), width, height)

                            Connections {
                                target: WeatherState
                                function onHoursChanged() { canvas.requestPaint(); }
                            }
                            Connections {
                                target: Style
                                function onFont_familyChanged() { canvas.requestPaint(); }
                                function onFont_sizeChanged() { canvas.requestPaint(); }
                                function onPalChanged() { canvas.requestPaint(); }
                                function onText_primaryChanged() { canvas.requestPaint(); }
                                function onText_mutedChanged() { canvas.requestPaint(); }
                            }
                            Connections {
                                target: root
                                function onSubChanged() { canvas.requestPaint(); }
                            }
                        }

                        Rectangle {
                            visible: root.hour_cursor >= 0 && root.hour_cursor < WeatherState.hours.length
                            x: root.hour_cursor * root.hour_col_w
                            width: root.hour_col_w
                            height: root.chart_h
                            color: Style.selection_bg
                            border.width: 1
                            border.color: Style.selection_border
                        }

                        Rectangle {
                            y: root.chart_h
                            width: parent.width
                            height: 1
                            color: Style.hairline
                        }

                        Repeater {
                            model: WeatherState.hours

                            Item {
                                id: hour_col
                                required property var modelData
                                required property int index

                                x: hour_col.index * root.hour_col_w
                                y: root.chart_h + 4
                                width: root.hour_col_w
                                height: root.icon_row_h + root.label_row_h

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.on_select(hour_col.index)
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    visible: hour_col.index === root.hour_cursor
                                    color: Style.selection_bg
                                    border.width: 1
                                    border.color: Style.selection_border
                                }

                                Image {
                                    visible: root.sub !== 2
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: root.icon_row_h
                                    height: root.icon_row_h
                                    sourceSize.width: root.icon_row_h * 2
                                    sourceSize.height: root.icon_row_h * 2
                                    source: WeatherState.icon_source(hour_col.modelData.code, hour_col.modelData.is_day)
                                    smooth: true
                                }

                                Text {
                                    visible: root.sub === 2
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: -(root.label_row_h / 2)
                                    text: "▲"
                                    rotation: hour_col.modelData.wind_dir
                                    color: root.hl
                                    font.pixelSize: Style.font_size
                                }

                                Text {
                                    anchors.top: parent.top
                                    anchors.topMargin: root.icon_row_h
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: WeatherState.format_hour(new Date(hour_col.modelData.dt))
                                    color: hour_col.index === root.hour_cursor ? root.hl : root.hl_t
                                    font.family: Style.number_font
                                    font.pixelSize: Style.fs(-3)
                                    font.bold: hour_col.index === root.hour_cursor
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
