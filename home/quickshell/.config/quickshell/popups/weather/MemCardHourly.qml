// home/quickshell/.config/quickshell/popups/weather/MemCardHourly.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"

// The hours as memory card saves: each hour a save block with its weather icon under a stack of used blocks that
// reads the sub's value, the selected hour lifted and lit with its readout above as the save's info panel.
// sub: 0 temp, 1 precip (chance + amount), 2 wind, 3 UV, 4 humidity. h/l move the hour cursor (auto-scrolling into view).
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    readonly property var sub_names: ["TEMP", "PRECIP", "WIND", "UV", "HUMID"]
    readonly property var secondary_names: ["FEELS", "", "GUST", "", ""]
    readonly property int card_blocks: 15
    readonly property int block_gap: 2
    readonly property int stack_w: 30
    // Heavy rain in the forecast's own unit, so amount text and the readout agree in mm and inches.
    readonly property real precip_full_scale: WeatherState.metric ? 5 : 0.2

    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]
    readonly property bool cursor_valid: !!root.cursor_row

    function scroll_to_cursor() {
        track.scroll_to_cursor();
    }

    function request_scroll() {
        track.request_scroll();
    }

    function secondary_of(hrs) {
        return root.sub === 0 ? hrs.map(r => r.feels) : root.sub === 2 ? hrs.map(r => r.wind_gusts) : null;
    }

    // The dashed secondary series shares the scale, so gusts above the speeds stay on the plot.
    function scale_range(hrs) {
        const values = hrs.map(track.value_of).concat(root.secondary_of(hrs) || []);
        if (root.sub === 1 || root.sub === 4) return { lo: 0, hi: 100 };
        if (root.sub === 3) return { lo: 0, hi: Math.max(12, Math.max(...values) + 1) };
        if (root.sub === 2) return { lo: 0, hi: Math.max(10, Math.max(...values)) };
        let lo = Math.min(...values);
        let hi = Math.max(...values);
        const pad = Math.max(2, (hi - lo) * 0.15);
        return { lo: lo - pad, hi: hi + pad };
    }

    function frac_of(v, range) {
        return Math.max(0, Math.min(1, (v - range.lo) / (range.hi - range.lo || 1)));
    }

    function block_color(frac, range) {
        const v = range.lo + (range.hi - range.lo) * frac;
        if (root.sub === 0) return WeatherState.temp_color(v);
        if (root.sub === 1) return Theme.info;
        if (root.sub === 2) return Style.pal.cyan;
        if (root.sub === 3) return WeatherState.uv_color(v);
        return Theme.theme_primary_light;
    }

    function value_text(v) {
        if (root.sub === 3) return v.toFixed(1);
        return Math.round(v) + (root.sub === 1 || root.sub === 4 ? "%" : root.sub === 0 ? "°" : "");
    }

    function amount_text(r) {
        return r.precip.toFixed(r.precip < 1 ? 2 : 1);
    }

    readonly property int top_pad: 20
    readonly property int bottom_pad: root.sub === 1 ? Style.fs(-6) + 6 : 2

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return;

        const values = hrs.map(track.value_of);
        const range = root.scale_range(hrs);
        const plot_h = h - root.top_pad - root.bottom_pad;
        const block_h = Math.max(2, (plot_h - root.block_gap * (root.card_blocks - 1)) / root.card_blocks);
        const block_y = b => root.top_pad + plot_h - (b + 1) * block_h - b * root.block_gap;
        const level_y = frac => root.top_pad + plot_h - frac * plot_h;
        const small = Style.fs(-5) + "px \"" + Style.font_family + "\"";

        ctx.strokeStyle = Style.text_muted;
        ctx.globalAlpha = 0.5;
        ctx.lineWidth = 1;
        ctx.setLineDash([2, 3]);
        for (const b of track.day_boundaries) {
            const x = Math.round(track.left_of(b.index)) + 0.5;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
        }
        ctx.setLineDash([]);
        ctx.globalAlpha = 1;
        ctx.fillStyle = Theme.theme_primary_light;
        ctx.font = small;
        ctx.textAlign = "left";
        for (const b of track.day_boundaries) ctx.fillText(b.label.toUpperCase(), track.left_of(b.index) + 4, 10);

        for (let i = 0; i < hrs.length; i++) {
            const selected = i === root.hour_cursor;
            const used = Math.max(1, Math.round(root.frac_of(values[i], range) * root.card_blocks));
            const x = Math.round(track.x_of(i) - root.stack_w / 2);
            for (let b = 0; b < root.card_blocks; b++) {
                const y = Math.round(block_y(b));
                const bh = Math.round(block_h);
                if (b >= used) {
                    ctx.globalAlpha = 0.45;
                    ctx.fillStyle = Theme.bg_shadow;
                    ctx.fillRect(x, y, root.stack_w, bh);
                    ctx.globalAlpha = 0.6;
                    ctx.strokeStyle = Style.frame_border_color;
                    ctx.lineWidth = 1;
                    ctx.strokeRect(x + 0.5, y + 0.5, root.stack_w - 1, bh - 1);
                    continue;
                }
                const color = root.block_color((b + 0.5) / root.card_blocks, range);
                const marked = selected && b === used - 1;
                ctx.globalAlpha = marked || selected ? 0.95 : 0.6;
                ctx.fillStyle = color;
                ctx.fillRect(x, y, root.stack_w, bh);
                ctx.globalAlpha = 1;
                ctx.strokeStyle = marked ? Style.text_strong : Qt.lighter(color, 1.3);
                ctx.lineWidth = marked ? 2 : 1;
                ctx.strokeRect(x + (marked ? 1 : 0.5), y + (marked ? 1 : 0.5), root.stack_w - (marked ? 2 : 1), bh - (marked ? 2 : 1));
            }
            ctx.globalAlpha = 1;
            ctx.fillStyle = selected ? Style.text_strong : Style.text_fg;
            ctx.font = small;
            ctx.textAlign = "center";
            ctx.fillText(root.value_text(values[i]), track.x_of(i), Math.max(12, level_y(root.frac_of(values[i], range)) - 5));
        }

        const secondary = root.secondary_of(hrs);
        if (secondary) {
            ctx.setLineDash([4, 3]);
            ctx.strokeStyle = Style.text_strong;
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            for (let i = 0; i < hrs.length; i++) {
                const x = track.x_of(i), y = level_y(root.frac_of(secondary[i], range));
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            ctx.stroke();
            ctx.setLineDash([]);
        }

        if (root.sub === 1) {
            ctx.fillStyle = Theme.info;
            ctx.font = small;
            ctx.textAlign = "center";
            for (let i = 0; i < hrs.length; i++) ctx.fillText(root.amount_text(hrs[i]), track.x_of(i), h - 2);
        }
    }

    onHour_cursorChanged: track.request_paint()

    readonly property string title: {
        const r = root.cursor_row;
        return r ? WeatherState.format_hour(new Date(r.dt)).toUpperCase() + "  " + r.cond.toUpperCase() : "";
    }

    readonly property string day_text: {
        const r = root.cursor_row;
        return r ? Qt.formatDate(new Date(r.date + "T00:00:00"), "ddd d").toUpperCase() : "";
    }

    readonly property string detail: {
        const r = root.cursor_row;
        if (!r) return "";
        const unit = WeatherState.metric ? " MM" : " IN";
        const parts = [Math.round(r.temp) + "°" + WeatherState.unit_symbol(), "FEELS " + Math.round(r.feels) + "°", r.pop + "% POP", r.precip.toFixed(2) + unit];
        return parts.join("  ");
    }

    readonly property string detail_two: {
        const r = root.cursor_row;
        if (!r) return "";
        const parts = ["WIND " + Math.round(r.wind_speed) + " " + WeatherState.wind_unit().toUpperCase() + " " + WeatherState.compass_label(r.wind_dir), "GUST " + Math.round(r.wind_gusts), "UV " + r.uv_index.toFixed(1), "HUM " + r.humidity + "%"];
        return parts.join("  ");
    }

    // The cursor hour's value for the readout's gauge, on the same scale as the stacks.
    readonly property real gauge_value: {
        if (!root.cursor_valid) return 0;
        return root.frac_of(track.value_of(root.cursor_row), root.scale_range(WeatherState.hours));
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: info.implicitHeight + 16
            radius: 6
            color: Qt.alpha(Theme.bg_shadow, 0.35)
            border.width: 2
            border.color: Style.frame_border_color

            RowLayout {
                id: info
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 10

                SaveIcon {
                    Layout.alignment: Qt.AlignTop
                    size: 44
                    code: root.cursor_valid ? root.cursor_row.code : -1
                    is_day: root.cursor_valid ? root.cursor_row.is_day : true
                    lit: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.title
                            color: Style.text_strong
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-1)
                            style: Text.Raised
                            styleColor: Style.text_shadow
                        }

                        Text {
                            text: root.day_text
                            color: Theme.theme_primary_light
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.detail
                        color: Style.text_fg
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-5)
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.detail_two
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-5)
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 3
                        spacing: 6

                        Text {
                            text: root.sub_names[root.sub]
                            color: Theme.theme_primary_light
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-5)
                        }

                        BlockGauge {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            value: root.gauge_value
                            fill_color: root.cursor_valid ? root.block_color(Math.max(0.05, root.gauge_value), root.scale_range(WeatherState.hours)) : Theme.theme_primary_light
                            mark_last: true
                        }

                        Text {
                            text: root.cursor_valid ? root.value_text(track.value_of(root.cursor_row)) : ""
                            color: Style.text_strong
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-5)
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 6
            color: Qt.alpha(Theme.bg_shadow, 0.35)
            border.width: 2
            border.color: Style.frame_border_color
            clip: true

            Rectangle {
                id: strip
                x: 4
                y: 4
                width: parent.width - 8
                height: strip_text.implicitHeight + 4
                radius: 3
                color: "transparent"

                FadeFill {
                    radius: parent.radius
                    fill: Style.title_bg
                }

                Text {
                    id: strip_text
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.sub_names[root.sub]
                    color: Style.title_fg
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                    style: Text.Raised
                    styleColor: Style.text_shadow
                }

                Text {
                    visible: root.secondary_names[root.sub] !== ""
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: "- - " + root.secondary_names[root.sub]
                    color: Style.text_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                }
            }

            HourlyTrack {
                id: track
                anchors.fill: parent
                anchors.topMargin: strip.y + strip.height + 4
                anchors.leftMargin: 3
                anchors.rightMargin: 3
                anchors.bottomMargin: 6
                icon_row_h: 38
                label_row_h: 16
                hour_cursor: root.hour_cursor
                sub: root.sub
                on_select: i => root.on_select(i)
                scroll_x: root.scroll_x
                on_scroll: x => root.on_scroll(x)
                paint: root.paint
                label_px: Style.fs(-5)

                underlay: Rectangle {
                    visible: root.cursor_valid
                    x: track.left_of(root.hour_cursor) + 2
                    width: track.hour_col_w - 4
                    height: track.chart_h + track.icon_row_h + track.label_row_h + 4
                    radius: 4
                    color: Qt.alpha(Style.selection_bg, 0.55)
                    border.width: 2
                    border.color: Theme.theme_primary_light
                }

                cell: Component {
                    Item {
                        id: hour_col
                        required property var modelData
                        required property int index
                        readonly property bool selected: hour_col.index === root.hour_cursor
                        // The lit save's icon bobs between two frames, as a BIOS save icon animates.
                        property bool frame_up: false

                        x: track.left_of(hour_col.index)
                        y: track.chart_h + 4
                        width: track.hour_col_w
                        height: track.icon_row_h + track.label_row_h

                        Timer {
                            running: hour_col.selected && Power.on_ac
                            interval: 450
                            repeat: true
                            onTriggered: hour_col.frame_up = !hour_col.frame_up
                            onRunningChanged: if (!running) hour_col.frame_up = false
                        }

                        SaveIcon {
                            x: (hour_col.width - width) / 2
                            y: hour_col.selected ? (hour_col.frame_up ? 1 : 3) : 4
                            size: 34
                            code: root.sub === 2 ? -1 : hour_col.modelData.code
                            is_day: hour_col.modelData.is_day
                            lit: hour_col.selected

                            Text {
                                visible: root.sub === 2
                                anchors.centerIn: parent
                                text: "▲"
                                rotation: hour_col.modelData.wind_dir
                                color: Style.pal.cyan
                                font.pixelSize: Style.font_size
                            }
                        }

                        Text {
                            anchors.top: parent.top
                            anchors.topMargin: track.icon_row_h
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: WeatherState.format_hour(new Date(hour_col.modelData.dt)).toUpperCase()
                            color: hour_col.selected ? Style.text_strong : Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-5)
                        }
                    }
                }
            }
        }
    }
}
