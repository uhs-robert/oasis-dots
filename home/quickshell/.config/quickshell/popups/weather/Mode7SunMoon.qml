// home/quickshell/.config/quickshell/popups/weather/Mode7SunMoon.qml
import QtQuick
import QtQuick.Layouts
import "../../components/snes" as Snes
import "../../theme"
import "../../services"

// A Mode 7 horizon: the selected day's sun arcing over the perspective floor (today's live position marked), the moon in the sky with its phase,
// and the sun and moon figures in an RPG window under a strip of day windows.
Item {
    id: root

    property int day_cursor: 0
    property int first_day: 0
    property int day_span: 5
    property var on_select: function (i) {}

    readonly property var day: WeatherState.days[Math.max(0, Math.min(WeatherState.days.length - 1, root.day_cursor))]
    readonly property bool is_today: root.day_cursor === 0

    readonly property var moon_times: root.day ? WeatherState.moon_times_for_date(root.day.date) : ({ rise: null, set: null })
    readonly property real moon_phase: root.day ? WeatherState.moon_phase_for_date(root.day.date) : 0
    readonly property string next_full: root.day ? WeatherState.next_full_moon_label(root.day.date) : ""

    // The location clock only moves on the minute.
    property int clock_tick: 0
    readonly property real rise_minutes: root.hm_minutes(root.day ? root.day.sunrise : "")
    readonly property real set_minutes: root.hm_minutes(root.day ? root.day.sunset : "")
    readonly property bool has_sun: root.rise_minutes >= 0 && root.set_minutes > root.rise_minutes
    readonly property real now_minutes: {
        root.clock_tick;
        const loc = WeatherState.location_now();
        return loc.getUTCHours() * 60 + loc.getUTCMinutes();
    }
    readonly property bool sun_up: root.is_today && root.has_sun && root.now_minutes >= root.rise_minutes && root.now_minutes <= root.set_minutes
    // Other days show the sun at solar noon, dimmed, so the arc always has its sun.
    readonly property real sun_fraction: root.sun_up ? (root.now_minutes - root.rise_minutes) / (root.set_minutes - root.rise_minutes) : root.is_today ? -1 : 0.5
    readonly property bool night: root.is_today && !root.sun_up
    readonly property bool scene_live: root.visible && Popups.open_name === "weather"

    function hm_minutes(hm) {
        const parts = (hm || "").split(":");
        return parts.length === 2 ? parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10) : -1;
    }

    function day_length() {
        if (!root.has_sun) return "—";
        const mins = root.set_minutes - root.rise_minutes;
        return Math.floor(mins / 60) + "H " + (mins % 60) + "M";
    }

    function upper(text) {
        return (text || "").toUpperCase();
    }

    onDay_cursorChanged: if (root.scene_live && floor_loader.item) floor_loader.item.run()

    onScene_liveChanged: {
        if (!floor_loader.item) return;
        if (root.scene_live) floor_loader.item.run();
        else floor_loader.item.stop();
    }

    Timer {
        interval: 60000
        running: root.is_today
        repeat: true
        onTriggered: root.clock_tick++
    }

    FontMetrics {
        id: big_metrics
        font.family: Style.font_family
        font.pixelSize: Style.font_size
    }

    FontMetrics {
        id: small_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-8)
    }

    // A figure in the stats window: the label dim, the value at the larger Silkscreen step when it fits.
    component StatRow: Item {
        id: stat
        property string label: ""
        property string value: ""

        Layout.fillWidth: true
        implicitHeight: Style.font_size

        Text {
            id: stat_label
            anchors.left: parent.left
            anchors.baseline: stat_value.baseline
            text: stat.label
            color: Style.pal.primary_light
            font.family: Style.font_family
            font.pixelSize: Style.fs(-8)
            style: Text.Raised
            styleColor: Style.text_shadow
        }

        Text {
            id: stat_value
            readonly property string shown: stat.value || "—"
            readonly property real room: stat.width - label_w.width - 6
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(0, stat_value.room))
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            text: stat_value.shown
            color: Style.pal.fg_strong
            font.family: Style.font_family
            font.pixelSize: big_metrics.advanceWidth(stat_value.shown) <= stat_value.room ? Style.font_size : Style.fs(-8)
            style: Text.Raised
            styleColor: Style.text_shadow
        }
    }

    // Fixed label column so every value starts from the same edge.
    Item {
        id: label_w
        width: small_metrics.advanceWidth("FULL MOON") + 4
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: WeatherState.days.slice(root.first_day, root.first_day + root.day_span)

                Snes.SnesWindow {
                    id: day_cell
                    required property var modelData
                    required property int index
                    readonly property int day_index: root.first_day + day_cell.index
                    readonly property bool selected: day_cell.day_index === root.day_cursor
                    readonly property string name: root.upper(day_cell.modelData.weekday)

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: Style.font_size + 18
                    radius: 3
                    drop: 2
                    lit: day_cell.selected

                    Text {
                        anchors.centerIn: day_cell.panel
                        width: Math.min(implicitWidth, day_cell.panel.width - 8)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: day_cell.name
                        color: day_cell.selected ? Style.pal.secondary : Style.pal.primary_light
                        font.family: Style.font_family
                        font.pixelSize: big_metrics.advanceWidth(day_cell.name) <= day_cell.panel.width - 8 ? Style.font_size : Style.fs(-8)
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(day_cell.day_index)
                    }
                }
            }
        }

        Snes.SnesWindow {
            id: scene_window
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 120

            Item {
                id: stage
                anchors.fill: scene_window.panel
                anchors.margins: 6
                clip: true

                readonly property real horizon: Math.round(stage.height * 0.56)

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0; color: root.night ? Qt.tint(Style.pal.bg_crust, Qt.alpha(Style.pal.primary_strong, 0.18)) : Qt.tint(Style.pal.bg_crust, Qt.alpha(Style.pal.primary_strong, 0.6)) }
                        GradientStop { position: 0.56; color: root.night ? Qt.tint(Style.pal.bg_crust, Qt.alpha(Style.pal.primary_light, 0.18)) : Qt.tint(Style.pal.bg_crust, Qt.alpha(Style.pal.primary_light, 0.45)) }
                        GradientStop { position: 0.561; color: Qt.tint(Style.pal.bg_crust, Qt.alpha(Style.pal.primary_strong, 0.25)) }
                        GradientStop { position: 1; color: Qt.tint(Style.pal.bg_crust, Qt.alpha(Style.pal.primary_strong, 0.25)) }
                    }
                }

                Loader {
                    id: floor_loader
                    y: stage.horizon
                    width: stage.width
                    height: stage.height - stage.horizon
                    sourceComponent: Mode7Floor {}
                    onLoaded: if (root.scene_live) floor_loader.item.run()
                }

                Canvas {
                    id: sky
                    anchors.fill: parent

                    // The grid unit of the sky's pixel art.
                    readonly property int cell: 2
                    readonly property real cx: sky.width / 2
                    readonly property real rx: Math.max(10, sky.width / 2 - 28)
                    readonly property real ry: Math.max(10, stage.horizon - 34)
                    readonly property var stars: [[0.06, 0.1], [0.14, 0.32], [0.23, 0.14], [0.31, 0.26], [0.4, 0.08], [0.49, 0.2], [0.58, 0.12], [0.66, 0.3], [0.74, 0.1], [0.83, 0.24], [0.9, 0.12], [0.95, 0.34]]

                    function dot(ctx, x, y, size) {
                        ctx.fillRect(Math.round(x - size / 2), Math.round(y - size / 2), size, size);
                    }

                    function draw_sun(ctx, x, y, alpha) {
                        const c = sky.cell;
                        ctx.globalAlpha = alpha;
                        for (let dy = -5; dy <= 5; dy++) {
                            for (let dx = -5; dx <= 5; dx++) {
                                const d = dx * dx + dy * dy;
                                if (d > 28) continue;
                                ctx.fillStyle = String(d > 16 ? Style.pal.yellow : Style.pal.bright_yellow);
                                if (dx === -2 && dy === -2) ctx.fillStyle = String(Style.pal.fg_strong);
                                ctx.fillRect(Math.round(x) + dx * c - c / 2, Math.round(y) + dy * c - c / 2, c, c);
                            }
                        }
                        ctx.fillStyle = String(Style.pal.yellow);
                        for (let k = 0; k < 8; k++) {
                            const a = k * Math.PI / 4;
                            const r = k % 2 === 0 ? 9 : 8;
                            ctx.fillRect(Math.round(x + Math.cos(a) * r * c) - c, Math.round(y + Math.sin(a) * r * c) - c, c * 2, c * 2);
                        }
                        ctx.globalAlpha = 1;
                    }

                    // Waxing moons are lit on the right; the terminator slides across as the phase advances.
                    function draw_moon(ctx, x, y, phase) {
                        const r = 6;
                        const c = 3;
                        const k = Math.cos(2 * Math.PI * phase);
                        for (let dy = -r; dy <= r; dy++) {
                            const half = Math.sqrt(Math.max(0, r * r - dy * dy));
                            for (let dx = -r; dx <= r; dx++) {
                                if (dx * dx + dy * dy > r * r + 1) continue;
                                const u = half > 0 ? dx / half : 0;
                                const lit = phase < 0.5 ? u > k : u < -k;
                                ctx.fillStyle = String(lit ? Style.pal.fg_strong : Qt.tint(Style.pal.bg_crust, Qt.alpha(Style.pal.primary_light, 0.35)));
                                ctx.fillRect(Math.round(x) + dx * c - c / 2, Math.round(y) + dy * c - c / 2, c, c);
                            }
                        }
                    }

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const w = sky.width, hz = stage.horizon;
                        if (w <= 0 || hz <= 0) return;

                        if (root.night) {
                            ctx.fillStyle = String(Style.pal.fg_strong);
                            ctx.globalAlpha = 0.8;
                            for (const s of sky.stars) sky.dot(ctx, s[0] * w, s[1] * hz, 2);
                            ctx.globalAlpha = 1;
                        }

                        ctx.save();
                        ctx.beginPath();
                        ctx.rect(0, 0, w, hz);
                        ctx.clip();

                        if (root.has_sun) {
                            const steps = Math.max(8, Math.round(Math.PI * sky.rx / 9));
                            for (let i = 0; i <= steps; i++) {
                                const f = i / steps;
                                const a = Math.PI * f;
                                const passed = root.sun_fraction >= 0 && root.is_today && f <= root.sun_fraction;
                                ctx.fillStyle = String(passed ? Style.pal.yellow : Style.pal.fg_strong);
                                ctx.globalAlpha = passed ? 0.9 : 0.4;
                                sky.dot(ctx, sky.cx - sky.rx * Math.cos(a), hz - sky.ry * Math.sin(a), 2);
                            }
                            ctx.globalAlpha = 1;

                            if (root.sun_fraction >= 0) {
                                const a = Math.PI * root.sun_fraction;
                                sky.draw_sun(ctx, sky.cx - sky.rx * Math.cos(a), hz - sky.ry * Math.sin(a), root.sun_up ? 1 : 0.45);
                            }
                        }
                        ctx.restore();

                        sky.draw_moon(ctx, w - 34, 30, root.moon_phase);
                    }

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    Connections {
                        target: root
                        function onDayChanged() { sky.requestPaint(); }
                        function onNow_minutesChanged() { sky.requestPaint(); }
                        function onMoon_phaseChanged() { sky.requestPaint(); }
                    }

                    Connections {
                        target: Style
                        function onPalChanged() { sky.requestPaint(); }
                    }
                }

                Text {
                    x: 8
                    y: 6
                    text: root.day ? root.day.date.substr(5).replace("-", "/") : ""
                    color: Style.pal.primary_light
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-8)
                    style: Text.Raised
                    styleColor: Style.text_shadow
                }

                Column {
                    x: 8
                    y: stage.horizon + 10
                    Text { text: "RISE"; color: Style.pal.primary_light; font.family: Style.font_family; font.pixelSize: Style.fs(-8); style: Text.Raised; styleColor: Style.text_shadow }
                    Text { text: root.day ? root.upper(WeatherState.fmt_hm(root.day.sunrise)) || "—" : ""; color: Style.pal.bright_yellow; font.family: Style.font_family; font.pixelSize: Style.font_size; style: Text.Raised; styleColor: Style.text_shadow }
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: stage.horizon + 10
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "DAYLIGHT"; color: Style.pal.primary_light; font.family: Style.font_family; font.pixelSize: Style.fs(-8); style: Text.Raised; styleColor: Style.text_shadow }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.day_length(); color: Style.pal.fg_strong; font.family: Style.font_family; font.pixelSize: Style.font_size; style: Text.Raised; styleColor: Style.text_shadow }
                }

                Column {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    y: stage.horizon + 10
                    Text { anchors.right: parent.right; text: "SET"; color: Style.pal.primary_light; font.family: Style.font_family; font.pixelSize: Style.fs(-8); style: Text.Raised; styleColor: Style.text_shadow }
                    Text { anchors.right: parent.right; text: root.day ? root.upper(WeatherState.fmt_hm(root.day.sunset)) || "—" : ""; color: Style.pal.bright_yellow; font.family: Style.font_family; font.pixelSize: Style.font_size; style: Text.Raised; styleColor: Style.text_shadow }
                }
            }
        }

        Snes.SnesWindow {
            id: stats_window
            Layout.fillWidth: true
            implicitHeight: stats.implicitHeight + 24

            GridLayout {
                id: stats
                anchors.left: stats_window.panel.left
                anchors.right: stats_window.panel.right
                anchors.verticalCenter: stats_window.panel.verticalCenter
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                columns: 2
                columnSpacing: 16
                rowSpacing: 6

                StatRow { label: "SUNRISE"; value: root.day ? root.upper(WeatherState.fmt_hm(root.day.sunrise)) : "" }
                StatRow { label: "SUNSET"; value: root.day ? root.upper(WeatherState.fmt_hm(root.day.sunset)) : "" }
                StatRow { label: "DAY"; value: root.day_length() }
                StatRow { label: "MOON"; value: root.day ? root.upper(WeatherState.moon_name(root.moon_phase)) : "" }
                StatRow { label: "MOONRISE"; value: root.upper(root.moon_times.rise) }
                StatRow { label: "MOONSET"; value: root.upper(root.moon_times.set) }
                StatRow { label: "FULL MOON"; value: root.upper(root.next_full) }
            }
        }
    }
}
