// home/quickshell/.config/quickshell/popups/weather/WsHourly.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../services"

// WeatherStar 4000+ "Hourly Graph": a bold line over a gridded blue panel, scrolling left to right.
// sub: 0 temp, 1 precip (chance + amount), 2 wind, 3 UV, 4 humidity.
// h/l move the hour cursor (auto-scrolling into view); H/L jump +-1 day, same hour.
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    readonly property var sub_names: ["Temperature", "Precipitation", "Wind", "UV Index", "Humidity"]
    readonly property var line_colors: [Theme.theme_secondary, Theme.fg_strong, Style.pal.bright_cyan, Theme.theme_label, Theme.theme_primary_light]

    readonly property int hour_col_w: 56
    readonly property int icon_row_h: 30
    readonly property int label_row_h: 18
    readonly property int axis_w: Style.px(34)
    readonly property int plot_top: 30
    readonly property int amount_px: Style.fs(-4)
    readonly property real readout_h: Math.max(18, readout_text.implicitHeight)
    readonly property int chart_h: flick.height - root.icon_row_h - root.label_row_h - 4
    readonly property int plot_bottom: root.sub === 1 ? root.amount_px + 6 : 0
    readonly property real plot_h: Math.max(1, root.chart_h - root.plot_top - root.plot_bottom)

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

    function secondary_of(row) {
        return root.sub === 0 ? row.feels : root.sub === 2 ? row.wind_gusts : null;
    }

    // Grid lines land on round values, and the axis extends to the outer ones so the line never leaves the panel.
    readonly property var axis: {
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return { min: 0, max: 1, ticks: [0, 1] };
        if (root.sub === 1 || root.sub === 4) return { min: 0, max: 100, ticks: [0, 25, 50, 75, 100] };
        let lo = 0, hi = 1;
        if (root.sub === 3) {
            hi = Math.max(12, ...hrs.map(root.value_of));
        } else {
            const all = hrs.map(root.value_of).concat(hrs.map(root.secondary_of).filter(v => v !== null));
            lo = Math.min(...all);
            hi = Math.max(...all);
        }
        const raw_step = Math.max(1, (hi - lo) / 4);
        const mag = Math.pow(10, Math.floor(Math.log10(raw_step)));
        const step = [1, 2, 5, 10].map(m => m * mag).find(s => s >= raw_step);
        const first = root.sub === 3 ? 0 : Math.floor(lo / step) * step;
        const last = Math.ceil(hi / step) * step;
        const ticks = [];
        for (let v = first; v <= last + step / 2; v += step) ticks.push(v);
        return { min: first, max: last, ticks: ticks };
    }

    function y_of(v) {
        const frac = (v - root.axis.min) / (root.axis.max - root.axis.min || 1);
        return root.plot_top + root.plot_h - frac * root.plot_h;
    }

    function tick_label(v) {
        return root.sub === 1 || root.sub === 4 ? v + "%" : root.sub === 0 ? v + "°" : "" + v;
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

    // The channel's lettering is white-on-blue with a dark drop shadow; canvas text has no outline style, so offset a dark copy.
    function shadowed_text(ctx, text, x, y, color) {
        ctx.fillStyle = Theme.bg_shadow;
        ctx.fillText(text, x + 1, y + 1);
        ctx.fillStyle = color;
        ctx.fillText(text, x, y);
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0 || root.chart_h <= 0) return;

        const x_of = i => i * root.hour_col_w + root.hour_col_w / 2;
        const color = root.line_colors[root.sub];
        const base_y = root.plot_top + root.plot_h;

        ctx.lineWidth = 1;
        ctx.strokeStyle = Theme.theme_primary_light;
        ctx.globalAlpha = 0.45;
        for (const t of root.axis.ticks) {
            const y = Math.round(root.y_of(t)) + 0.5;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(w, y);
            ctx.stroke();
        }
        for (const b of root.day_boundaries) {
            const x = Math.round(b.index * root.hour_col_w) + 0.5;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
        }
        ctx.globalAlpha = 1;

        ctx.font = Style.fs(-3) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "left";
        for (const b of root.day_boundaries) root.shadowed_text(ctx, b.label, b.index * root.hour_col_w + 4, 13, Theme.theme_primary_light);

        if (root.sub === 1) {
            ctx.beginPath();
            ctx.moveTo(x_of(0), base_y);
            for (let i = 0; i < hrs.length; i++) ctx.lineTo(x_of(i), root.y_of(hrs[i].pop));
            ctx.lineTo(x_of(hrs.length - 1), base_y);
            ctx.closePath();
            ctx.fillStyle = Theme.theme_primary_strong;
            ctx.globalAlpha = 0.35;
            ctx.fill();
            ctx.globalAlpha = 1;
        }

        // Dashed secondary line: feels-like for temp, gusts for wind.
        if (root.sub === 0 || root.sub === 2) {
            ctx.setLineDash([4, 3]);
            ctx.strokeStyle = Theme.theme_primary_light;
            ctx.lineWidth = 2;
            ctx.beginPath();
            for (let i = 0; i < hrs.length; i++) {
                const x = x_of(i), y = root.y_of(root.secondary_of(hrs[i]));
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            ctx.stroke();
            ctx.setLineDash([]);
        }

        ctx.lineJoin = "round";
        ctx.lineWidth = 5;
        ctx.strokeStyle = Theme.bg_shadow;
        ctx.beginPath();
        for (let i = 0; i < hrs.length; i++) {
            const x = x_of(i), y = root.y_of(root.value_of(hrs[i]));
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.stroke();
        ctx.lineWidth = 3;
        ctx.strokeStyle = color;
        ctx.stroke();

        ctx.textAlign = "center";
        for (let i = 0; i < hrs.length; i++) {
            const v = root.value_of(hrs[i]);
            const label = root.sub === 3 ? v.toFixed(1) : Math.round(v) + (root.sub === 1 || root.sub === 4 ? "%" : root.sub === 0 ? "°" : "");
            root.shadowed_text(ctx, label, x_of(i), Math.max(root.plot_top - 2, root.y_of(v) - 8), Theme.fg_strong);
        }

        if (root.sub === 1) {
            ctx.font = root.amount_px + "px \"" + Style.font_family + "\"";
            for (let i = 0; i < hrs.length; i++) root.shadowed_text(ctx, hrs[i].precip.toFixed(hrs[i].precip < 1 ? 2 : 1), x_of(i), h - 3, Theme.theme_primary_light);
        }
    }

    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]

    readonly property string readout: {
        const r = root.cursor_row;
        if (!r) return "";
        const parts = [WeatherState.format_hour(new Date(r.dt)), Math.round(r.temp) + "°" + WeatherState.unit_symbol(), r.pop + "% pop", r.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in"), r.cond];
        return parts.join(" · ");
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Hourly Graph"
                color: Theme.theme_secondary
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
                style: Text.Outline
                styleColor: Theme.bg_shadow
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: root.sub_names[root.sub] + (root.sub === 0 ? " (" + WeatherState.unit_symbol() + ")" : root.sub === 2 ? " (" + WeatherState.wind_unit() + ")" : "")
                color: root.line_colors[root.sub]
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
                style: Text.Outline
                styleColor: Theme.bg_shadow
            }
        }

        Text {
            id: readout_text
            Layout.fillWidth: true
            Layout.preferredHeight: root.readout_h
            text: root.readout
            color: Theme.fg_strong
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
            style: Text.Outline
            styleColor: Theme.bg_shadow
            elide: Text.ElideRight
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            WsPanel {
                anchors.fill: parent
            }

            Item {
                id: axis_col
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 4
                anchors.topMargin: 4
                width: root.axis_w

                Repeater {
                    model: root.axis.ticks

                    Text {
                        required property real modelData
                        width: axis_col.width
                        horizontalAlignment: Text.AlignRight
                        y: root.y_of(modelData) - implicitHeight / 2
                        text: root.tick_label(modelData)
                        color: Theme.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-3)
                        style: Text.Outline
                        styleColor: Theme.bg_shadow
                    }
                }
            }

            Flickable {
                id: flick
                anchors.left: axis_col.right
                anchors.leftMargin: 4
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.top: parent.top
                anchors.topMargin: 4
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
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

                    Rectangle {
                        visible: root.hour_cursor >= 0 && root.hour_cursor < WeatherState.hours.length
                        x: root.hour_cursor * root.hour_col_w
                        width: root.hour_col_w
                        height: parent.height
                        color: Qt.alpha(Theme.theme_secondary, 0.14)
                        border.width: 2
                        border.color: Theme.theme_secondary
                    }

                    Canvas {
                        id: canvas
                        width: parent.width
                        height: root.chart_h
                        onPaint: root.paint(getContext("2d"), width, height)
                        onHeightChanged: requestPaint()

                        Connections {
                            target: WeatherState
                            function onHoursChanged() { canvas.requestPaint(); }
                        }
                        Connections {
                            target: Style
                            function onFont_familyChanged() { canvas.requestPaint(); }
                            function onFont_sizeChanged() { canvas.requestPaint(); }
                            function onPalChanged() { canvas.requestPaint(); }
                        }
                        Connections {
                            target: root
                            function onSubChanged() { canvas.requestPaint(); }
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

                            Image {
                                visible: root.sub !== 2
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: root.icon_row_h
                                height: root.icon_row_h
                                readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                                sourceSize.width: Math.ceil(root.icon_row_h * 2 * dpr)
                                sourceSize.height: Math.ceil(root.icon_row_h * 2 * dpr)
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
                                color: Style.pal.bright_cyan
                                font.pixelSize: Style.font_size
                            }

                            Text {
                                anchors.top: parent.top
                                anchors.topMargin: root.icon_row_h
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: WeatherState.format_hour(new Date(hour_col.modelData.dt))
                                color: hour_col.index === root.hour_cursor ? Theme.theme_secondary : Theme.fg_strong
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-3)
                                style: Text.Outline
                                styleColor: Theme.bg_shadow
                            }
                        }
                    }
                }
            }
        }
    }
}
