// home/quickshell/.config/quickshell/popups/weather/PrecipView.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// Next 12 hours: bars for chance of precipitation, labels for amount. h/l move the cursor.
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property var slice: WeatherState.hours.slice(0, 12)
    readonly property var cursor_row: root.slice[Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))]

    readonly property string readout: {
        const r = root.cursor_row;
        if (!r) return "";
        return [WeatherState.format_hour(new Date(r.dt)), r.pop + "% pop", r.precip.toFixed(2) + (WeatherState.settings.unit === "celsius" ? " mm" : " in"), r.cond].join(" · ");
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        Text {
            Layout.preferredHeight: 18
            text: root.readout
            color: Theme.fg_core
            font.family: Style.font_family
            font.pixelSize: Style.font_size - 2
        }

        Canvas {
            id: canvas
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property var rows: root.slice

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const w = width, h = height;
                const rows = canvas.rows;
                if (rows.length === 0) return;

                const margin_bottom = 32;
                const margin_top = 26;
                const chart_h = h - margin_bottom - margin_top;
                const col_w = w / rows.length;

                ctx.strokeStyle = Style.text_muted;
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(0, margin_top + chart_h);
                ctx.lineTo(w, margin_top + chart_h);
                ctx.stroke();

                ctx.font = (Style.font_size - 2) + "px \"" + Style.font_family + "\"";
                ctx.textAlign = "center";

                for (let i = 0; i < rows.length; i++) {
                    const row = rows[i];
                    const bar_w = Math.max(6, col_w * 0.5);
                    const bar_h = (Math.max(0, Math.min(100, row.pop)) / 100) * chart_h;
                    const x = i * col_w + (col_w - bar_w) / 2;
                    const y = margin_top + chart_h - bar_h;

                    if (i === root.hour_cursor) {
                        ctx.fillStyle = Theme.bg_surface;
                        ctx.fillRect(i * col_w, margin_top, col_w, chart_h);
                    }

                    ctx.fillStyle = WeatherState.pop_color(row.pop);
                    ctx.fillRect(x, y, bar_w, bar_h);

                    ctx.fillStyle = Style.text_dim;
                    ctx.fillText(row.pop + "%", i * col_w + col_w / 2, y - 6 < margin_top ? margin_top : y - 6);

                    ctx.fillStyle = i === root.hour_cursor ? Theme.theme_secondary : Style.text_muted;
                    ctx.fillText(WeatherState.format_hour(new Date(row.dt)), i * col_w + col_w / 2, h - margin_bottom + 16);

                    ctx.fillStyle = Theme.blue;
                    ctx.fillText(row.precip.toFixed(row.precip < 1 ? 2 : 1), i * col_w + col_w / 2, margin_top - 8);
                }
            }

            Connections {
                target: WeatherState
                function onHoursChanged() { canvas.requestPaint(); }
            }
            Connections {
                target: Style
                function onFont_familyChanged() { canvas.requestPaint(); }
            }
            Connections {
                target: root
                function onHour_cursorChanged() { canvas.requestPaint(); }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: mouse => {
                    const rows = canvas.rows;
                    if (rows.length === 0) return;
                    const idx = Math.max(0, Math.min(rows.length - 1, Math.floor(mouse.x / (width / rows.length))));
                    root.on_select(idx);
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Bars: chance of precipitation · Numbers: amount (" + (WeatherState.settings.unit === "celsius" ? "mm" : "in") + ")"
            color: Style.text_dim
            font.family: Style.font_family
            font.pixelSize: Style.font_size - 3
        }
    }
}
