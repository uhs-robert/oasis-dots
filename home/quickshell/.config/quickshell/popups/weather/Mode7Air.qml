import QtQuick
import QtQuick.Layouts
import qs.components
import qs.components.snes as Snes
import qs.theme
import qs.services

// The next 24 hours of AQI as gauge pillars on the Mode 7 floor, a kart parked at the cursor hour, and the current air in an RPG status window:
// AQI, category, a status ailment once the air turns unhealthy, and the pollutants as gauges. h/l move the hour cursor.
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
    readonly property bool scene_live: root.visible && Popups.open_name === "weather"

    readonly property int aqi: root.ready ? WeatherState.aq_current.aqi : 0
    readonly property color aqi_tone: root.ready ? WeatherState.aqi_color(root.aqi) : Style.text_dim
    // The EPA's own short name keeps the longest category on one line.
    readonly property string category: root.ready ? WeatherState.aqi_band(root.aqi).label.replace("Unhealthy for Sensitive Groups", "USG").toUpperCase() : ""
    // Unhealthy for sensitive groups poisons; very unhealthy and worse is fatal.
    readonly property int ailment_level: root.aqi >= 201 ? 2 : root.aqi >= 101 ? 1 : 0

    // Concentrations (ug/m3) at which each pollutant's gauge is full.
    readonly property var pollutants: [
        { label: "PM2.5", key: "pm25", full: 75 },
        { label: "PM10", key: "pm10", full: 150 },
        { label: "OZONE", key: "ozone", full: 200 }
    ]

    readonly property int top_pad: 44
    readonly property int foot_h: 18
    readonly property int pillar_w: 10
    readonly property int cap_h: 5
    readonly property real horizon_frac: 0.4

    // Stepped, not eased: SNES menu cursors jump whole pixels.
    property int bob: 0

    SequentialAnimation {
        running: root.scene_live && root.cursor_row !== undefined
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.bob = 0
        PropertyAction { target: root; property: "bob"; value: 0 }
        PauseAnimation { duration: 180 }
        PropertyAction { target: root; property: "bob"; value: 2 }
        PauseAnimation { duration: 180 }
        PropertyAction { target: root; property: "bob"; value: 3 }
        PauseAnimation { duration: 180 }
        PropertyAction { target: root; property: "bob"; value: 2 }
        PauseAnimation { duration: 180 }
    }

    FontMetrics {
        id: label_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-8)
    }

    readonly property real label_w: label_metrics.advanceWidth(WeatherState.format_hour(new Date(2000, 0, 1, 12)).toUpperCase()) + 8
    readonly property real col_w: root.slice.length > 0 ? stage.width / root.slice.length : stage.width
    readonly property real chart_h: stage.height - root.foot_h
    readonly property real max_v: Math.max(100, ...root.slice.map(r => r.aqi))

    function x_of(i) {
        return (i + 0.5) * root.col_w;
    }

    function top_of(aqi) {
        const frac = Math.max(0.03, Math.min(1, aqi / root.max_v));
        return Math.round(root.chart_h - frac * (root.chart_h - root.top_pad));
    }

    function label_step() {
        return [2, 3, 4, 6, 8, 12].find(n => n * root.col_w >= root.label_w) || 12;
    }

    function shadowed_text(ctx, text, x, y, color) {
        ctx.fillStyle = String(Style.text_shadow);
        ctx.fillText(text, x + 1, y + 1);
        ctx.fillStyle = String(color);
        ctx.fillText(text, x, y);
    }

    function ellipse(ctx, cx, cy, rx, ry) {
        ctx.save();
        ctx.translate(cx, cy);
        ctx.scale(1, ry / rx);
        ctx.beginPath();
        ctx.arc(0, 0, rx, 0, 2 * Math.PI);
        ctx.restore();
    }

    function pillar(ctx, cx, y_top, base, color, selected) {
        const pw = root.pillar_w;
        const x0 = Math.round(cx - pw / 2);
        const shade = Qt.tint(color, Qt.alpha(Style.pal.fg_strong, 0.4));

        ctx.globalAlpha = 0.5;
        ctx.fillStyle = String(Style.pal.bg_shadow);
        root.ellipse(ctx, cx, base + 1, pw * 0.75, root.cap_h);
        ctx.fill();
        ctx.globalAlpha = 1;

        const body = ctx.createLinearGradient(0, y_top, 0, base);
        body.addColorStop(0, String(shade));
        body.addColorStop(1, String(color));
        ctx.fillStyle = body;
        ctx.fillRect(x0, y_top, pw, base - y_top);
        ctx.globalAlpha = 0.35;
        ctx.fillStyle = String(Style.pal.bg_crust);
        for (let y = base - 8; y > y_top; y -= 8) ctx.fillRect(x0, y, pw, 1);
        ctx.globalAlpha = 0.28;
        ctx.fillStyle = String(Style.pal.fg_strong);
        ctx.fillRect(x0 + 2, y_top, 2, base - y_top);
        ctx.globalAlpha = 0.45;
        ctx.fillStyle = String(Style.pal.bg_shadow);
        ctx.fillRect(x0 + Math.round(pw * 0.62), y_top, pw - Math.round(pw * 0.62), base - y_top);
        ctx.globalAlpha = 1;

        ctx.fillStyle = String(Style.pal.bg_shadow);
        root.ellipse(ctx, cx, base, pw / 2, root.cap_h / 2);
        ctx.fill();
        root.ellipse(ctx, cx, y_top, pw / 2, root.cap_h / 2);
        ctx.fillStyle = String(selected ? Style.pal.fg_strong : Style.pal.primary_light);
        ctx.fill();
        ctx.strokeStyle = String(selected ? Style.pal.secondary : Style.pal.fg_muted);
        ctx.lineWidth = 1;
        ctx.stroke();
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const rows = root.slice;
        if (rows.length === 0) return;
        const base = root.chart_h;
        const family = "\"" + Style.font_family + "\"";

        if (root.cursor_index >= 0) {
            ctx.fillStyle = String(Qt.alpha(Style.pal.secondary, 0.14));
            ctx.fillRect(Math.round(root.cursor_index * root.col_w) + 1, 0, Math.round(root.col_w) - 2, base);
        }

        ctx.font = Style.fs(-8) + "px " + family;
        ctx.textAlign = "center";
        const step = root.label_step();
        for (let i = 0; i < rows.length; i++) {
            const selected = i === root.cursor_index;
            root.pillar(ctx, Math.round(root.x_of(i)), root.top_of(rows[i].aqi), base, WeatherState.aqi_color(rows[i].aqi), selected);
            const crowds_cursor = Math.abs(i - root.cursor_index) * root.col_w < root.label_w;
            if (selected || (i % step === 0 && !crowds_cursor)) {
                const text = WeatherState.format_hour(new Date(rows[i].dt)).toUpperCase();
                const half = ctx.measureText(text).width / 2;
                root.shadowed_text(ctx, text, Math.max(half, Math.min(w - half - 1, root.x_of(i))), h - 5, selected ? Style.pal.fg_strong : Style.pal.primary_light);
            }
        }
    }

    onCursor_indexChanged: {
        pillars.requestPaint();
        if (root.scene_live && floor_loader.item) floor_loader.item.run();
    }

    onScene_liveChanged: {
        if (!floor_loader.item) return;
        if (root.scene_live) floor_loader.item.run();
        else floor_loader.item.stop();
    }

    Text {
        anchors.centerIn: parent
        visible: !root.ready
        text: WeatherState.aq_loading ? "Loading…" : "Air quality unavailable"
        color: Style.text_dim
        font.family: Style.font_family
        font.pixelSize: Style.font_size
        style: Text.Raised
        styleColor: Style.text_shadow
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        visible: root.ready

        Snes.SnesWindow {
            id: status_window
            Layout.fillWidth: true
            implicitHeight: status.implicitHeight + 22

            ColumnLayout {
                id: status
                anchors.left: status_window.panel.left
                anchors.right: status_window.panel.right
                anchors.verticalCenter: status_window.panel.verticalCenter
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: "AQI"
                        Layout.alignment: Qt.AlignBaseline
                        color: Style.pal.primary_light
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-8)
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }

                    Text {
                        Layout.alignment: Qt.AlignBaseline
                        text: root.aqi
                        color: root.aqi_tone
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(20)
                        font.bold: true
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.alignment: Qt.AlignBaseline
                        elide: Text.ElideRight
                        text: root.category
                        color: root.aqi_tone
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }

                    Ailment {
                        visible: root.ailment_level > 0
                        Layout.alignment: Qt.AlignVCenter
                        level: root.ailment_level
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: root.pollutants

                        ColumnLayout {
                            id: pollutant
                            required property var modelData
                            readonly property var value: WeatherState.aq_current[pollutant.modelData.key]
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: pollutant.modelData.label
                                    color: Style.pal.primary_light
                                    font.family: Style.font_family
                                    font.pixelSize: Style.fs(-8)
                                    style: Text.Raised
                                    styleColor: Style.text_shadow
                                }

                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideLeft
                                    text: pollutant.value !== null && pollutant.value !== undefined ? pollutant.value.toFixed(1) : "--"
                                    color: Style.pal.fg_strong
                                    font.family: Style.font_family
                                    font.pixelSize: Style.fs(-8)
                                    style: Text.Raised
                                    styleColor: Style.text_shadow
                                }
                            }

                            Snes.SnesGauge {
                                Layout.fillWidth: true
                                value: pollutant.value ? pollutant.value / pollutant.modelData.full : 0
                                hot_from: 0.8
                            }
                        }
                    }
                }
            }
        }

        Snes.SnesWindow {
            id: scene_window
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                id: stage
                anchors.fill: scene_window.panel
                anchors.margins: 6
                clip: true

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.tint(Style.pal.bg_crust, Qt.alpha(Style.pal.primary_strong, 0.55)) }
                        GradientStop { position: 1; color: Qt.tint(Style.pal.bg_crust, Qt.alpha(Style.pal.primary_light, 0.3)) }
                    }
                }

                Rectangle {
                    y: Math.round(root.chart_h * root.horizon_frac)
                    width: parent.width
                    height: root.chart_h - y + 4
                    color: Qt.tint(Style.pal.bg_crust, Qt.alpha(Style.pal.primary_strong, 0.25))
                }

                Loader {
                    id: floor_loader
                    y: Math.round(root.chart_h * root.horizon_frac)
                    width: parent.width
                    height: root.chart_h - y + 4
                    sourceComponent: Mode7Floor {}
                    onLoaded: if (root.scene_live) floor_loader.item.run()
                }

                Rectangle {
                    y: root.chart_h + 4
                    width: parent.width
                    height: parent.height - y
                    color: Qt.alpha(Style.pal.bg_crust, 0.7)
                }

                Text {
                    x: 6
                    y: 4
                    width: parent.width - 12
                    elide: Text.ElideRight
                    readonly property var r: root.cursor_row
                    text: r ? (WeatherState.format_hour(new Date(r.dt)) + "  AQI " + r.aqi + "  " + WeatherState.aqi_band(r.aqi).label).toUpperCase() : ""
                    color: Style.pal.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-8)
                    style: Text.Raised
                    styleColor: Style.text_shadow
                }

                Canvas {
                    id: pillars
                    anchors.fill: parent
                    antialiasing: false
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: root.paint(getContext("2d"), width, height)

                    Connections {
                        target: WeatherState
                        function onAq_hoursChanged() { pillars.requestPaint(); }
                    }
                    Connections {
                        target: Style
                        function onFont_familyChanged() { pillars.requestPaint(); }
                        function onNameChanged() { pillars.requestPaint(); }
                    }
                    Connections {
                        target: TimeFormat
                        function onH24Changed() { pillars.requestPaint(); }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: mouse => {
                            if (root.slice.length === 0) return;
                            root.on_select(Math.max(0, Math.min(root.slice.length - 1, Math.floor(mouse.x / root.col_w))));
                        }
                    }
                }

                // The cursor hand over the selected pillar, then the kart parked at its foot.
                Column {
                    visible: root.cursor_row !== undefined
                    x: Math.round(root.x_of(root.cursor_index)) - width / 2
                    y: root.top_of(root.cursor_row ? root.cursor_row.aqi : 0) - root.cap_h / 2 - 13 + root.bob

                    Repeater {
                        model: [10, 6, 2]

                        Rectangle {
                            required property var modelData
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: modelData
                            height: 2
                            color: Style.pal.fg_strong
                        }
                    }
                }

                PixelSprite {
                    visible: root.cursor_row !== undefined
                    pixel: 2
                    colors: [Style.pal.bg_crust, Style.pal.red, Style.pal.fg_strong, Style.pal.fg_dim, Style.pal.secondary]
                    rows: ["...00000...", "..0444440..", "..0422240..", "...00000...", ".0011111100", "00111111100", "33011111033", "33.00000.33"]
                    x: Math.round(root.x_of(root.cursor_index) - width / 2)
                    y: root.chart_h - height - 1 + (root.bob === 3 ? 1 : 0)
                }
            }
        }
    }

    // A status-menu ailment badge: a poison drop, or a skull once the air is lethal.
    component Ailment: RowLayout {
        id: ailment
        property int level: 1
        spacing: 5

        PixelSprite {
            pixel: 2
            colors: ailment.level === 2 ? [Style.pal.bg_crust, Style.pal.fg_strong, Style.pal.bg_crust] : [Style.pal.bg_crust, Style.pal.magenta, Style.pal.fg_strong]
            rows: ailment.level === 2
                ? [".0000000.", "011111110", "012111210", "011111110", ".0111110.", ".0101010.", "..00000.."]
                : ["...00...", "..0110..", "..0110..", ".012110.", ".011110.", ".011110.", "..0110..", "...00..."]
        }

        Text {
            text: ailment.level === 2 ? "DOOM" : "POISON"
            color: ailment.level === 2 ? Style.pal.fg_strong : Style.pal.magenta
            font.family: Style.font_family
            font.pixelSize: Style.fs(-8)
            style: Text.Raised
            styleColor: Style.text_shadow
        }
    }
}
