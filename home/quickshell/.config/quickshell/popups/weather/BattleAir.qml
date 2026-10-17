import QtQuick
import QtQuick.Layouts
import qs.ui.effects
import qs.theme
import qs.services
import "../../styles/nes/widgets/Slimes.js" as Slimes

// Hourly's Air sub-view as a Dragon Quest encounter: the air is the monster, its pollutants are its stat lines,
// and the 24 hours are a strip of gauges with a king slime hopping on the cursor hour. h/l move the hour cursor.
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property var slice: WeatherState.aq_hours.slice(0, 24)
    // The cursor is shared with the longer hourly range, so it is clamped to these 24 hours.
    readonly property int cursor_index: Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))
    readonly property var cursor_row: root.slice[root.cursor_index]

    readonly property bool ready: WeatherState.aq_has_data && !!WeatherState.aq_current
    readonly property int aqi: root.ready ? WeatherState.aq_current.aqi : -1
    readonly property color aqi_tone: root.ready ? WeatherState.aqi_color(root.aqi) : Style.text_dim
    // "Unhealthy for Sensitive Groups" and worse.
    readonly property bool poisoned: root.aqi >= 151

    readonly property bool animating: Popups.open_name === "weather" && root.visible && Power.on_ac

    readonly property int sprite_pixel: 2
    readonly property int sprite_h: Slimes.KING_SLIME.length * root.sprite_pixel

    // Pollutant concentration (ug/m3) that fills a stat gauge: roughly where each pollutant is Unhealthy on the US AQI scale.
    readonly property var stat_lines: [
        { label: "PM2.5", key: "pm25", full: 150 },
        { label: "PM10", key: "pm10", full: 250 },
        { label: "OZONE", key: "ozone", full: 200 }
    ]

    BattlePalette {
        id: palette
    }

    readonly property var enemy_colors: {
        const colors = palette.colors.slice();
        if (root.poisoned) {
            colors[4] = Style.pal.magenta;
            colors[5] = Style.pal.bright_magenta;
        }
        return colors;
    }

    function stat_value(key) {
        return WeatherState.aq_current ? WeatherState.aq_current[key] : null;
    }

    function hour_label(row) {
        return WeatherState.format_hour(new Date(row.dt)).toUpperCase();
    }

    DqWindow {
        anchors.fill: parent
        visible: !root.ready

        Text {
            anchors.centerIn: parent
            text: WeatherState.aq_loading ? "Loading…" : "Air quality unavailable"
            color: Style.text_dim
            font.family: Style.font_family
            font.pixelSize: Style.font_size
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        visible: root.ready

        DqWindow {
            Layout.fillWidth: true
            implicitHeight: enemy.implicitHeight + 24

            RowLayout {
                id: enemy
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 14

                Item {
                    Layout.preferredWidth: Slimes.SIZE * 5
                    Layout.preferredHeight: Slimes.SIZE * 5
                    Layout.alignment: Qt.AlignVCenter

                    PixelSprite {
                        id: slime
                        pixel: 5
                        colors: root.enemy_colors
                        rows: Slimes.SLIME
                        transform: Translate { y: slime.hopped ? -5 : 0 }

                        property bool hopped: false

                        Timer {
                            running: root.animating
                            interval: root.poisoned ? 350 : 600
                            repeat: true
                            onTriggered: slime.hopped = !slime.hopped
                            onRunningChanged: if (!running) slime.hopped = false
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: root.aqi
                            color: root.aqi_tone
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(4)
                            font.bold: true
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: root.ready ? WeatherState.aqi_band(root.aqi).label.toUpperCase() : ""
                            color: root.aqi_tone
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                        }

                        Text {
                            visible: root.poisoned
                            text: "POISON"
                            color: Style.pal.magenta
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-5)
                            font.bold: true
                        }
                    }

                    // Widest label and value, so every gauge starts and ends on the same column.
                    Text {
                        id: label_width
                        visible: false
                        text: "OZONE"
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-5)
                    }

                    Text {
                        id: value_width
                        visible: false
                        text: "000.0"
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-5)
                    }

                    Repeater {
                        model: root.stat_lines

                        RowLayout {
                            id: stat
                            required property var modelData
                            readonly property var value: root.stat_value(stat.modelData.key)

                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                Layout.preferredWidth: label_width.implicitWidth
                                text: stat.modelData.label
                                color: Style.text_muted
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-5)
                            }

                            BattleGauge {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                value: stat.value !== null ? stat.value / stat.modelData.full : 0
                                fill_color: root.aqi_tone
                            }

                            Text {
                                Layout.preferredWidth: value_width.implicitWidth
                                horizontalAlignment: Text.AlignRight
                                text: stat.value !== null ? stat.value.toFixed(1) : "--"
                                color: Style.pal.fg_strong
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-5)
                            }
                        }
                    }
                }
            }
        }

        DqWindow {
            Layout.fillWidth: true
            implicitHeight: hour_line.implicitHeight + 20

            RowLayout {
                id: hour_line
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                Text {
                    text: Style.row_cursor
                    color: Style.caret_color
                    visible: !!root.cursor_row && Style.caret_phase
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                }

                Text {
                    text: root.cursor_row ? root.hour_label(root.cursor_row) : ""
                    color: Style.pal.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    visible: !!root.cursor_row
                    Layout.maximumWidth: hour_line.width * 0.7
                    elide: Text.ElideRight
                    text: root.cursor_row ? "AQI " + root.cursor_row.aqi + " · " + WeatherState.aqi_band(root.cursor_row.aqi).label : ""
                    color: root.cursor_row ? WeatherState.aqi_color(root.cursor_row.aqi) : Style.text_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                }
            }
        }

        DqWindow {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "AQI 24H"

            Canvas {
                id: strip
                anchors.fill: parent
                anchors.margins: 8

                readonly property int label_h: 14
                readonly property int top_pad: root.sprite_h + 6
                readonly property real chart_h: Math.max(1, strip.height - strip.top_pad - strip.label_h)
                readonly property real col_w: root.slice.length > 0 ? strip.width / root.slice.length : strip.width
                readonly property real scale_max: Math.max(100, ...root.slice.map(r => r.aqi))

                function fill_h(aqi) {
                    return Math.max(2, Math.round(Math.min(1, aqi / strip.scale_max) * (strip.chart_h - 4)));
                }

                function bar_x(i) {
                    return Math.round(i * strip.col_w + Math.max(1, strip.col_w * 0.15));
                }

                function bar_w() {
                    return Math.max(4, Math.round(strip.col_w * 0.7));
                }

                function cursor_x() {
                    return strip.bar_x(root.cursor_index) + strip.bar_w() / 2;
                }

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const rows = root.slice;
                    if (rows.length === 0) return;

                    const font = Style.fs(-6) + "px \"" + Style.font_family + "\"";
                    ctx.font = font;
                    ctx.textAlign = "center";
                    const label_w = ctx.measureText(root.hour_label({ dt: new Date(2000, 0, 1, 12) })).width + 8;
                    const step = [3, 4, 6, 8, 12].find(n => n * strip.col_w >= label_w) || 12;
                    const bw = strip.bar_w();

                    for (let i = 0; i < rows.length; i++) {
                        const x = strip.bar_x(i);
                        const selected = i === root.cursor_index;
                        const bottom = strip.top_pad + strip.chart_h;

                        ctx.fillStyle = Style.pal.bg_crust;
                        ctx.fillRect(x, strip.top_pad, bw, strip.chart_h);
                        ctx.fillStyle = selected ? Style.pal.fg_strong : Style.pal.fg_muted;
                        ctx.fillRect(x, strip.top_pad, bw, 1);
                        ctx.fillRect(x, bottom - 1, bw, 1);
                        ctx.fillRect(x, strip.top_pad, 1, strip.chart_h);
                        ctx.fillRect(x + bw - 1, strip.top_pad, 1, strip.chart_h);

                        const fh = strip.fill_h(rows[i].aqi);
                        ctx.globalAlpha = selected ? 1 : 0.8;
                        ctx.fillStyle = WeatherState.aqi_color(rows[i].aqi);
                        ctx.fillRect(x + 2, bottom - 2 - fh, bw - 4, fh);
                        ctx.globalAlpha = 1;

                        const clear_of_cursor = Math.abs(i - root.cursor_index) * strip.col_w >= label_w;
                        if (selected || (i % step === 0 && clear_of_cursor)) {
                            ctx.fillStyle = selected ? Style.pal.fg_strong : Style.text_muted;
                            ctx.fillText(root.hour_label(rows[i]), i * strip.col_w + strip.col_w / 2, strip.height - 3);
                        }
                    }
                }

                Connections {
                    target: WeatherState
                    function onAq_hoursChanged() { strip.requestPaint(); }
                }
                Connections {
                    target: Style
                    function onFont_familyChanged() { strip.requestPaint(); }
                    function onFont_sizeChanged() { strip.requestPaint(); }
                    function onPalChanged() { strip.requestPaint(); }
                    function onText_mutedChanged() { strip.requestPaint(); }
                }
                Connections {
                    target: TimeFormat
                    function onH24Changed() { strip.requestPaint(); }
                }
                Connections {
                    target: root
                    function onCursor_indexChanged() { strip.requestPaint(); }
                }

                PixelSprite {
                    id: king
                    visible: root.slice.length > 0
                    pixel: root.sprite_pixel
                    colors: palette.colors
                    rows: Slimes.KING_SLIME
                    x: Math.round(strip.cursor_x() - width / 2)
                    y: Math.max(0, strip.top_pad + strip.chart_h - 2 - (root.cursor_row ? strip.fill_h(root.cursor_row.aqi) : 0) - root.sprite_h + 1 - 2)
                    // The hop is a transform, so the slide Behavior on y does not animate it.
                    transform: Translate { y: king.hopped ? -root.sprite_pixel : 0 }

                    property bool hopped: false
                    property bool settled: false

                    Behavior on x {
                        enabled: king.settled
                        NumberAnimation { duration: 140 }
                    }

                    Behavior on y {
                        enabled: king.settled
                        NumberAnimation { duration: 140 }
                    }

                    Timer {
                        running: root.animating && king.visible
                        interval: 500
                        repeat: true
                        onTriggered: king.hopped = !king.hopped
                        onRunningChanged: if (!running) king.hopped = false
                    }

                    Component.onCompleted: Qt.callLater(() => { king.settled = true; })
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mouse => {
                        if (root.slice.length === 0) return;
                        root.on_select(Math.max(0, Math.min(root.slice.length - 1, Math.floor(mouse.x / strip.col_w))));
                    }
                }
            }
        }
    }
}
