// home/quickshell/.config/quickshell/popups/weather/HourlyView.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../services"

// Full-range scrollable line chart. sub: 0 temp, 1 precip, 2 wind, 3 UV, 4 humidity.
// h/l move the hour cursor (auto-scrolling into view); H/L jump +-1 day, same hour.
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property var sub_names: ["Temperature", "Precipitation", "Wind", "UV", "Humidity"]

    readonly property int hour_col_w: 56
    readonly property int icon_row_h: 30
    readonly property int label_row_h: 18
    readonly property int readout_h: 18
    readonly property int chart_h: root.height - root.readout_h - 8 - root.icon_row_h - root.label_row_h - 4

    readonly property var hour_colors: [Theme.yellow, Theme.blue, Theme.cyan, Theme.warning, Theme.bright_cyan]

    readonly property var day_boundaries: {
        const list = [];
        let last_date = null;
        const today_str = WeatherState.location_date_str();
        const hrs = WeatherState.hours;
        for (let i = 0; i < hrs.length; i++) {
            if (hrs[i].date !== last_date) {
                const label = hrs[i].date === today_str ? "Today" : Qt.formatDate(new Date(hrs[i].date + "T00:00:00"), "ddd");
                list.push({ index: i, label: label });
                last_date = hrs[i].date;
            }
        }
        return list;
    }

    function value_of(row) {
        return [row.temp, row.pop, row.wind_speed, row.uv_index, row.humidity][root.sub];
    }

    function scroll_to_cursor() {
        const cursor_x = root.hour_cursor * root.hour_col_w;
        const margin = root.hour_col_w * 2;
        if (cursor_x < flick.contentX + margin) {
            flick.contentX = Math.max(0, cursor_x - margin);
        } else if (cursor_x + root.hour_col_w > flick.contentX + flick.width - margin) {
            flick.contentX = Math.min(Math.max(0, flick.contentWidth - flick.width), cursor_x + root.hour_col_w - flick.width + margin);
        }
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return;

        const values = hrs.map(root.value_of);
        let min_v, max_v;
        if (root.sub === 1 || root.sub === 4) { min_v = 0; max_v = 100; }
        else if (root.sub === 3) { min_v = 0; max_v = Math.max(12, Math.max(...values) + 1); }
        else {
            min_v = Math.min(...values);
            max_v = Math.max(...values);
            const pad = Math.max(2, (max_v - min_v) * 0.15);
            min_v -= pad;
            max_v += pad;
        }

        const top_pad = 20;
        const plot_h = h - top_pad;
        const y_of = v => top_pad + plot_h - ((v - min_v) / (max_v - min_v || 1)) * plot_h;
        const x_of = i => i * root.hour_col_w + root.hour_col_w / 2;
        const color = root.hour_colors[root.sub];

        ctx.strokeStyle = Theme.fg_muted;
        ctx.globalAlpha = 0.25;
        ctx.lineWidth = 1;
        for (const b of root.day_boundaries) {
            const x = b.index * root.hour_col_w;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
        }
        ctx.globalAlpha = 1;
        ctx.fillStyle = Theme.fg_muted;
        ctx.font = (Theme.popup_font_size - 2) + "px " + Theme.font_family;
        ctx.textAlign = "left";
        for (const b of root.day_boundaries) {
            ctx.fillText(b.label, b.index * root.hour_col_w + 3, 12);
        }

        if (root.sub === 1) {
            ctx.beginPath();
            ctx.moveTo(x_of(0), h);
            for (let i = 0; i < hrs.length; i++) ctx.lineTo(x_of(i), y_of(hrs[i].pop));
            ctx.lineTo(x_of(hrs.length - 1), h);
            ctx.closePath();
            ctx.fillStyle = Theme.blue;
            ctx.globalAlpha = 0.15;
            ctx.fill();
            ctx.globalAlpha = 1;
        }

        // Dimmer/dashed secondary line: feels-like for temp, gusts for wind.
        const secondary = root.sub === 0 ? hrs.map(r => r.feels) : root.sub === 2 ? hrs.map(r => r.wind_gusts) : null;
        if (secondary) {
            ctx.setLineDash([4, 3]);
            ctx.strokeStyle = Theme.fg_muted;
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            for (let i = 0; i < hrs.length; i++) {
                const x = x_of(i), y = y_of(secondary[i]);
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            ctx.stroke();
            ctx.setLineDash([]);
        }

        ctx.strokeStyle = color;
        ctx.lineWidth = 2.5;
        ctx.beginPath();
        for (let i = 0; i < hrs.length; i++) {
            const x = x_of(i), y = y_of(values[i]);
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.stroke();

        ctx.fillStyle = color;
        for (let i = 0; i < hrs.length; i++) {
            const x = x_of(i), y = y_of(values[i]);
            ctx.beginPath();
            ctx.arc(x, y, 3, 0, 2 * Math.PI);
            ctx.fill();
        }

        ctx.fillStyle = Theme.fg_core;
        ctx.textAlign = "center";
        for (let i = 0; i < hrs.length; i++) {
            const v = values[i];
            const x = x_of(i), y = y_of(v);
            const label = root.sub === 3 ? v.toFixed(1) : Math.round(v) + (root.sub === 1 || root.sub === 4 ? "%" : root.sub === 0 ? "°" : "");
            ctx.fillText(label, x, Math.max(12, y - 8));
        }

        // Crosshair at the selected hour.
        if (root.hour_cursor >= 0 && root.hour_cursor < hrs.length) {
            const cx = x_of(root.hour_cursor);
            ctx.strokeStyle = Theme.theme_secondary;
            ctx.globalAlpha = 0.5;
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(cx, 0);
            ctx.lineTo(cx, h);
            ctx.stroke();
            ctx.globalAlpha = 1;
        }
    }

    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]

    readonly property string readout: {
        const r = root.cursor_row;
        if (!r) return "";
        const parts = [WeatherState.format_hour(new Date(r.dt)), Math.round(r.temp) + "°" + WeatherState.unit_symbol(), r.pop + "% pop", r.precip.toFixed(2) + (WeatherState.settings.unit === "celsius" ? " mm" : " in"), r.cond];
        return parts.join(" · ");
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        Text {
            Layout.preferredHeight: root.readout_h
            text: root.readout
            color: Theme.fg_core
            font.family: Theme.font_family
            font.pixelSize: Theme.popup_font_size - 2
            elide: Text.ElideRight
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: WeatherState.hours.length * root.hour_col_w
            contentHeight: height
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick

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
                        target: root
                        function onSubChanged() { canvas.requestPaint(); }
                        function onHour_cursorChanged() { canvas.requestPaint(); }
                    }
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
                            color: Theme.bg_surface
                            radius: 3
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
                            color: Theme.cyan
                            font.pixelSize: Theme.popup_font_size
                        }

                        Text {
                            anchors.top: parent.top
                            anchors.topMargin: root.icon_row_h
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: WeatherState.format_hour(new Date(hour_col.modelData.dt))
                            color: hour_col.index === root.hour_cursor ? Theme.theme_secondary : Theme.fg_muted
                            font.family: Theme.font_family
                            font.pixelSize: Theme.popup_font_size - 2
                        }
                    }
                }
            }
        }
    }
}
