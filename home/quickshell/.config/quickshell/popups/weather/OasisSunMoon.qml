import QtQuick
import QtQuick.Layouts
import qs.components.oasis as Oasis
import qs.theme
import qs.services

// Oasis Sun & Moon: a day strip on a horizon, a desert scene where today's sun travels its arc and sinks behind the dunes
// (other days show the arc and the sun's noon ghost), sunrise/sunset/daylight in a card, and the moon over a small oasis pool.
Item {
    id: root

    property int day_cursor: 0
    property int first_day: 0
    property int day_span: 5
    property var on_select: function (i) {}

    readonly property color sand: Theme.theme_secondary
    readonly property color hair: Qt.alpha(Theme.theme_primary, 0.3)

    readonly property var day: WeatherState.days[Math.max(0, Math.min(WeatherState.days.length - 1, root.day_cursor))]
    readonly property bool is_today: root.day_cursor === 0

    readonly property var moon_times: root.day ? WeatherState.moon_times_for_date(root.day.date) : ({ rise: null, set: null })
    readonly property real moon_phase: root.day ? WeatherState.moon_phase_for_date(root.day.date) : 0
    readonly property string next_full: root.day ? WeatherState.next_full_moon_label(root.day.date) : ""

    function hm_minutes(hm) {
        if (!hm) return null;
        const parts = hm.split(":");
        if (parts.length !== 2) return null;
        return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
    }

    readonly property var rise_min: root.hm_minutes(root.day ? root.day.sunrise : "")
    readonly property var set_min: root.hm_minutes(root.day ? root.day.sunset : "")
    readonly property bool has_sun: root.rise_min !== null && root.set_min !== null && root.set_min > root.rise_min

    // Today's progress through the daylight: below 0 before sunrise, above 1 after sunset. Null on other days.
    function sun_fraction() {
        if (!root.is_today || !root.has_sun) return null;
        const loc = WeatherState.location_now();
        const now = loc.getUTCHours() * 60 + loc.getUTCMinutes();
        return (now - root.rise_min) / (root.set_min - root.rise_min);
    }

    function day_length() {
        if (!root.has_sun) return "—";
        const mins = root.set_min - root.rise_min;
        return Math.floor(mins / 60) + "h " + (mins % 60) + "m";
    }

    component StatLabel: Text {
        color: Theme.fg_dim
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
    }

    component Stat: ColumnLayout {
        id: stat
        property string label: ""
        property string value: ""
        property string detail: ""

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 1

        StatLabel {
            text: stat.label
        }

        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: stat.value || "—"
            color: Theme.fg_strong
            font.family: Style.number_font
            font.pixelSize: Style.fs(2)
            font.weight: Font.Light
            font.features: { "tnum": 1 }
        }

        Text {
            Layout.fillWidth: true
            visible: stat.detail !== ""
            elide: Text.ElideRight
            text: stat.detail
            color: Style.text_dim
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: WeatherState.days.slice(root.first_day, root.first_day + root.day_span)

                Item {
                    id: day_cell
                    required property var modelData
                    required property int index
                    readonly property int day_index: root.first_day + day_cell.index
                    readonly property bool selected: day_cell.day_index === root.day_cursor

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: day_name.implicitHeight + 14

                    Text {
                        id: day_name
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(implicitWidth, parent.width - 2)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: day_cell.modelData.weekday
                        color: day_cell.selected ? root.sand : Theme.fg_dim
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-3)
                        font.weight: day_cell.selected ? Font.DemiBold : Font.Medium
                    }

                    Rectangle {
                        x: -2
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 3
                        width: parent.width + 4
                        height: 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: day_cell.index === 0 ? "transparent" : root.hair }
                            GradientStop { position: 1; color: day_cell.index === root.day_span - 1 ? "transparent" : root.hair }
                        }
                    }

                    Rectangle {
                        visible: day_cell.selected
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: 11
                        height: 11
                        radius: 5.5
                        color: Theme.bg_mantle

                        Rectangle {
                            anchors.centerIn: parent
                            width: 7
                            height: 7
                            radius: 3.5
                            color: root.sand
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(day_cell.day_index)
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 110

            Canvas {
                id: scene
                anchors.fill: parent

                Timer {
                    interval: 60000
                    running: root.is_today
                    repeat: true
                    onTriggered: scene.requestPaint()
                }

                Connections {
                    target: root
                    function onDayChanged() { scene.requestPaint(); }
                }

                Connections {
                    target: Style
                    function onPalChanged() { scene.requestPaint(); }
                }

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                function rounded_clip(ctx, w, h, r) {
                    ctx.beginPath();
                    ctx.moveTo(r, 0);
                    ctx.arcTo(w, 0, w, h, r);
                    ctx.arcTo(w, h, 0, h, r);
                    ctx.arcTo(0, h, 0, 0, r);
                    ctx.arcTo(0, 0, w, 0, r);
                    ctx.closePath();
                }

                // Rolling dune line: two sines so neighbouring layers never line up.
                function dune_y(x, base, amp, period, phase) {
                    return base - amp * (0.65 * Math.sin(x / period + phase) + 0.35 * Math.sin(x / (period * 0.43) + phase * 2.1));
                }

                function dune_layer(ctx, w, h, base, amp, period, phase, fill, crest) {
                    ctx.beginPath();
                    ctx.moveTo(0, h);
                    for (let x = 0; x <= w; x += 3) ctx.lineTo(x, scene.dune_y(x, base, amp, period, phase));
                    ctx.lineTo(w, h);
                    ctx.closePath();
                    ctx.fillStyle = fill;
                    ctx.fill();
                    ctx.strokeStyle = crest;
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    for (let x = 0; x <= w; x += 3) {
                        const y = scene.dune_y(x, base, amp, period, phase);
                        if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                    }
                    ctx.stroke();
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const w = width, h = height;
                    const frac = root.sun_fraction();
                    // Sky brightness: 1 with the sun high, 0 at night; other days show a fixed fair-weather dusk.
                    const light = frac === null ? 0.55 : frac < 0 || frac > 1 ? 0 : Math.min(1, Math.sin(Math.PI * frac) * 2.5);
                    const edge = frac === null ? 0.3 : Math.max(0, 1 - Math.min(Math.abs(frac), Math.abs(frac - 1)) / 0.22);

                    scene.rounded_clip(ctx, w, h, Style.radius(8));
                    ctx.save();
                    ctx.clip();

                    const night = Theme.bg_crust;
                    const noon = Qt.tint(Theme.bg_mantle, Qt.alpha(Theme.theme_primary_strong, 0.7));
                    const glow = Qt.tint(Theme.theme_secondary, Qt.alpha(Theme.theme_label, 0.45));
                    const horizon = h - 42;
                    const top_color = Qt.tint(night, Qt.alpha(noon, light));
                    const low_color = Qt.tint(Qt.tint(Theme.bg_mantle, Qt.alpha(Theme.theme_primary, 0.18)), Qt.alpha(Theme.theme_primary_light, 0.5 * light));
                    const sky = ctx.createLinearGradient(0, 0, 0, horizon + 10);
                    sky.addColorStop(0, top_color);
                    sky.addColorStop(0.62, Qt.tint(top_color, Qt.alpha(low_color, 0.8)));
                    sky.addColorStop(1, Qt.tint(low_color, Qt.alpha(glow, 0.75 * edge)));
                    ctx.fillStyle = sky;
                    ctx.fillRect(0, 0, w, h);

                    if (light < 0.6) {
                        ctx.fillStyle = Theme.fg_strong;
                        for (let i = 0; i < 26; i++) {
                            const sx = (i * 97 % 89) / 89 * w;
                            const sy = (i * 53 % 41) / 41 * (horizon - 24) + 6;
                            ctx.globalAlpha = (0.7 - light) * (0.35 + 0.65 * ((i * 31) % 7) / 7);
                            ctx.beginPath();
                            ctx.arc(sx, sy, i % 5 === 0 ? 1.1 : 0.7, 0, 2 * Math.PI);
                            ctx.fill();
                        }
                        ctx.globalAlpha = 1;
                    }

                    const cx = w / 2, rx = w * 0.38, ry = Math.max(20, horizon - 30);
                    const arc_point = f => ({ x: cx - rx * Math.cos(Math.PI * f), y: horizon - ry * Math.sin(Math.PI * f) });

                    ctx.lineCap = "round";
                    ctx.lineWidth = 1.5;
                    ctx.setLineDash([1, 5]);
                    ctx.strokeStyle = Qt.alpha(root.sand, 0.4);
                    ctx.beginPath();
                    for (let i = 0; i <= 80; i++) {
                        const p = arc_point(i / 80);
                        if (i === 0) ctx.moveTo(p.x, p.y); else ctx.lineTo(p.x, p.y);
                    }
                    ctx.stroke();
                    ctx.setLineDash([]);

                    if (frac !== null) {
                        const f = Math.max(-0.2, Math.min(1.2, frac));
                        if (frac > 0) {
                            ctx.strokeStyle = Qt.alpha(root.sand, 0.85);
                            ctx.lineWidth = 2;
                            ctx.beginPath();
                            const steps = Math.max(2, Math.round(Math.min(1, frac) * 60));
                            for (let i = 0; i <= steps; i++) {
                                const p = arc_point(Math.min(1, frac) * i / steps);
                                if (i === 0) ctx.moveTo(p.x, p.y); else ctx.lineTo(p.x, p.y);
                            }
                            ctx.stroke();
                        }
                        const sun = arc_point(f);
                        // A low sun reddens as it meets the dunes.
                        const disc = Qt.tint(root.sand, Qt.alpha(Theme.theme_label, 0.5 * edge));
                        const halo = ctx.createRadialGradient(sun.x, sun.y, 3, sun.x, sun.y, 34);
                        halo.addColorStop(0, Qt.alpha(disc, 0.6));
                        halo.addColorStop(1, Qt.alpha(disc, 0));
                        ctx.fillStyle = halo;
                        ctx.fillRect(sun.x - 34, sun.y - 34, 68, 68);
                        ctx.fillStyle = disc;
                        ctx.beginPath();
                        ctx.arc(sun.x, sun.y, 9, 0, 2 * Math.PI);
                        ctx.fill();
                    } else {
                        const apex = arc_point(0.5);
                        ctx.strokeStyle = Qt.alpha(root.sand, 0.5);
                        ctx.lineWidth = 1.5;
                        ctx.setLineDash([2, 3]);
                        ctx.beginPath();
                        ctx.arc(apex.x, apex.y, 9, 0, 2 * Math.PI);
                        ctx.stroke();
                        ctx.setLineDash([]);
                    }

                    const lit = 0.55 * light + 0.45 * edge;
                    const crest_color = Qt.alpha(root.sand, 0.25 + 0.3 * lit);
                    scene.dune_layer(ctx, w, h, horizon + 2, 9, 46, 0.6, Qt.tint(Theme.bg_mantle, Qt.alpha(root.sand, 0.1 + 0.16 * lit)), Qt.alpha(root.sand, 0.15 + 0.15 * lit));
                    scene.dune_layer(ctx, w, h, horizon + 16, 10, 61, 2.3, Qt.tint(Theme.bg_core, Qt.alpha(root.sand, 0.08 + 0.18 * lit)), crest_color);
                    ctx.strokeStyle = Qt.alpha(root.sand, 0.12);
                    for (let k = 1; k <= 2; k++) {
                        ctx.beginPath();
                        for (let x = 0; x <= w; x += 3) {
                            const y = scene.dune_y(x, horizon + 16, 10, 61, 2.3) + k * 6;
                            if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                        }
                        ctx.stroke();
                    }
                    scene.dune_layer(ctx, w, h, horizon + 34, 8, 38, 4.4, Qt.tint(Theme.bg_core, Qt.alpha(Theme.bg_crust, 0.7)), Qt.alpha(root.sand, 0.12 + 0.1 * lit));

                    ctx.restore();
                    ctx.strokeStyle = Style.frame_border_color;
                    ctx.lineWidth = 1;
                    scene.rounded_clip(ctx, w - 1, h - 1, Style.radius(8));
                    ctx.stroke();
                }
            }

            Oasis.OasisPalm {
                x: parent.width * 0.86
                y: parent.height - height - 4
                color: Qt.alpha(Theme.bg_crust, 0.95)
                stroke: 1.8
            }

            Text {
                x: 10
                y: 7
                text: root.day ? Qt.formatDate(new Date(root.day.date + "T00:00:00"), "dddd d MMMM") : ""
                color: Theme.fg_core
                opacity: 0.85
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
                font.weight: Font.DemiBold
            }
        }

        Oasis.OasisCard {
            Layout.fillWidth: true
            implicitHeight: stats_row.implicitHeight + 20

            RowLayout {
                id: stats_row
                anchors.fill: parent
                anchors.margins: 10
                anchors.leftMargin: 14
                spacing: 12

                Stat {
                    label: "SUNRISE"
                    value: root.day ? WeatherState.fmt_hm(root.day.sunrise) : ""
                }

                Stat {
                    label: "SUNSET"
                    value: root.day ? WeatherState.fmt_hm(root.day.sunset) : ""
                }

                Stat {
                    label: "DAYLIGHT"
                    value: root.day_length()
                }
            }
        }

        Oasis.OasisCard {
            Layout.fillWidth: true
            implicitHeight: moon_row.implicitHeight + 20

            RowLayout {
                id: moon_row
                anchors.fill: parent
                anchors.margins: 10
                anchors.leftMargin: 14
                spacing: 14

                Oasis.MoonPool {
                    Layout.preferredWidth: 112
                    Layout.preferredHeight: 92
                    phase: root.moon_phase
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: WeatherState.moon_name(root.moon_phase)
                        color: Theme.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(2)
                        font.weight: Font.DemiBold
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ColumnLayout {
                            spacing: 1
                            StatLabel { text: "MOONRISE" }
                            Text {
                                text: root.moon_times.rise || "—"
                                color: Theme.fg_core
                                font.family: Style.number_font
                                font.pixelSize: Style.fs(-1)
                                font.features: { "tnum": 1 }
                            }
                        }

                        ColumnLayout {
                            visible: !!root.moon_times.set
                            spacing: 1
                            StatLabel { text: "MOONSET" }
                            Text {
                                text: root.moon_times.set || ""
                                color: Theme.fg_core
                                font.family: Style.number_font
                                font.pixelSize: Style.fs(-1)
                                font.features: { "tnum": 1 }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "Full moon " + root.next_full
                        color: root.sand
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-3)
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }
}
