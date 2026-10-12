// home/quickshell/.config/quickshell/popups/weather/HeroSunMoon.qml
import QtQuick
import QtQuick.Layouts
import "../../components/modern" as Modern
import "../../theme"
import "../../services"

// Modern Sun & Moon: a day-pill strip, a sky card whose gradient runs dawn to dusk around the sun arc
// (today shows a glowing sun at its live position), sunrise/sunset/day-length tiles and a moon card.
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

    // Sky stretches this long before sunrise and after sunset, so twilight shows at the card's edges.
    readonly property real twilight_minutes: 120

    function hm_minutes(hm) {
        if (!hm) return null;
        const parts = hm.split(":");
        if (parts.length !== 2) return null;
        return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
    }

    readonly property var rise_min: root.hm_minutes(root.day ? root.day.sunrise : "")
    readonly property var set_min: root.hm_minutes(root.day ? root.day.sunset : "")
    readonly property bool has_sun: root.rise_min !== null && root.set_min !== null && root.set_min > root.rise_min

    function sun_fraction() {
        if (!root.is_today || !root.has_sun) return null;
        const loc = WeatherState.location_now();
        const now = loc.getUTCHours() * 60 + loc.getUTCMinutes();
        if (now < root.rise_min || now > root.set_min) return null;
        return (now - root.rise_min) / (root.set_min - root.rise_min);
    }

    function day_length() {
        if (!root.has_sun) return "—";
        const mins = root.set_min - root.rise_min;
        return Math.floor(mins / 60) + "h " + (mins % 60) + "m";
    }

    component StatTile: Modern.CardSurface {
        id: tile
        property string label: ""
        property string value: ""
        property string glyph: ""
        property color glyph_color: Theme.theme_secondary

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: tile_row.implicitHeight + 16

        RowLayout {
            id: tile_row
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: Qt.alpha(tile.glyph_color, 0.16)

                Text {
                    anchors.centerIn: parent
                    text: tile.glyph
                    color: tile.glyph_color
                    font.family: Style.mono_font
                    font.pixelSize: Style.fs(2)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: tile.label
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.4
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: tile.value || "—"
                    color: Style.text_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(1)
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }
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
                    implicitHeight: day_text.implicitHeight + 10

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: day_cell.selected ? "transparent" : Qt.alpha(Theme.fg_strong, 0.05)
                        gradient: day_cell.selected ? pill_gradient : null

                        Gradient {
                            id: pill_gradient
                            GradientStop { position: 0; color: Style.selection_shade.a > 0 ? Style.selection_shade : Style.selection_bg }
                            GradientStop { position: 1; color: Style.selection_bg }
                        }
                    }

                    Text {
                        id: day_text
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 8)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: day_cell.modelData.weekday
                        color: day_cell.selected ? Style.selection_fg : Style.text_dim
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                        font.weight: Font.DemiBold
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
            Layout.minimumHeight: 100

            Canvas {
                id: sky
                anchors.fill: parent

                Timer {
                    interval: 60000
                    running: root.is_today
                    repeat: true
                    onTriggered: sky.requestPaint()
                }

                function rounded_clip(ctx, w, h, r) {
                    ctx.beginPath();
                    ctx.moveTo(r, 0);
                    ctx.arcTo(w, 0, w, h, r);
                    ctx.arcTo(w, h, 0, h, r);
                    ctx.arcTo(0, h, 0, 0, r);
                    ctx.arcTo(0, 0, w, 0, r);
                    ctx.closePath();
                }

                // Colours are placed by clock time, so a long day pushes midday blue wider and a short one narrows it.
                function sky_gradient(ctx, w) {
                    const grad = ctx.createLinearGradient(0, 0, w, 0);
                    const span = root.has_sun ? root.set_min - root.rise_min + 2 * root.twilight_minutes : 1;
                    const at = minute => Math.max(0, Math.min(1, root.has_sun ? (minute - (root.rise_min - root.twilight_minutes)) / span : 0.5));
                    const rise = root.has_sun ? root.rise_min : 360, set = root.has_sun ? root.set_min : 1080;
                    const stops = [
                        [0, "#1f2650"],
                        [at(rise - 70), "#3b3566"],
                        [at(rise - 10), "#b9627f"],
                        [at(rise + 45), "#eca46c"],
                        [at(rise + 130), "#6fb4e8"],
                        [at(set - 130), "#62a9e6"],
                        [at(set - 45), "#eb9a60"],
                        [at(set + 10), "#b4566f"],
                        [at(set + 70), "#3b3566"],
                        [1, "#1f2650"]
                    ];
                    let last = 0;
                    for (const s of stops) {
                        last = Math.max(last, s[0]);
                        grad.addColorStop(last, s[1]);
                    }
                    return grad;
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const w = width, h = height;
                    const corner = Style.radius(10);
                    sky.rounded_clip(ctx, w, h, corner);
                    ctx.save();
                    ctx.clip();

                    ctx.globalAlpha = 0.88;
                    ctx.fillStyle = sky.sky_gradient(ctx, w);
                    ctx.fillRect(0, 0, w, h);
                    ctx.globalAlpha = 1;

                    const veil = ctx.createLinearGradient(0, 0, 0, h);
                    veil.addColorStop(0, "rgba(0,0,0,0)");
                    veil.addColorStop(1, "rgba(8,10,24,0.55)");
                    ctx.fillStyle = veil;
                    ctx.fillRect(0, 0, w, h);

                    const horizon = h - 26;
                    const x_at = minute => w * (minute - (root.rise_min - root.twilight_minutes)) / (root.set_min - root.rise_min + 2 * root.twilight_minutes);
                    const x_rise = root.has_sun ? x_at(root.rise_min) : w * 0.2;
                    const x_set = root.has_sun ? x_at(root.set_min) : w * 0.8;
                    const cx = (x_rise + x_set) / 2, rx = (x_set - x_rise) / 2, ry = Math.max(16, horizon - 22);

                    ctx.fillStyle = "rgba(8,10,24,0.5)";
                    ctx.fillRect(0, horizon, w, h - horizon);
                    ctx.strokeStyle = "rgba(255,255,255,0.28)";
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(0, horizon + 0.5);
                    ctx.lineTo(w, horizon + 0.5);
                    ctx.stroke();

                    const frac = root.sun_fraction();
                    const arc_point = f => {
                        const a = Math.PI - f * Math.PI;
                        return { x: cx + rx * Math.cos(a), y: horizon - ry * Math.sin(a) };
                    };
                    ctx.lineCap = "round";
                    ctx.lineWidth = 2;
                    ctx.setLineDash([1, 6]);
                    ctx.strokeStyle = "rgba(255,255,255,0.55)";
                    ctx.beginPath();
                    for (let i = 0; i <= 80; i++) {
                        const p = arc_point(i / 80);
                        if (i === 0) ctx.moveTo(p.x, p.y); else ctx.lineTo(p.x, p.y);
                    }
                    ctx.stroke();
                    ctx.setLineDash([]);

                    if (frac !== null) {
                        ctx.strokeStyle = "rgba(255,255,255,0.9)";
                        ctx.lineWidth = 2.5;
                        ctx.beginPath();
                        const steps = Math.max(2, Math.round(frac * 60));
                        for (let i = 0; i <= steps; i++) {
                            const p = arc_point(frac * i / steps);
                            if (i === 0) ctx.moveTo(p.x, p.y); else ctx.lineTo(p.x, p.y);
                        }
                        ctx.stroke();

                        const sun = arc_point(frac);
                        const glow = ctx.createRadialGradient(sun.x, sun.y, 2, sun.x, sun.y, 26);
                        glow.addColorStop(0, "rgba(255,226,140,0.95)");
                        glow.addColorStop(0.35, "rgba(255,200,90,0.45)");
                        glow.addColorStop(1, "rgba(255,190,80,0)");
                        ctx.fillStyle = glow;
                        ctx.fillRect(sun.x - 26, sun.y - 26, 52, 52);
                        ctx.fillStyle = "#fff3c4";
                        ctx.beginPath();
                        ctx.arc(sun.x, sun.y, 7, 0, 2 * Math.PI);
                        ctx.fill();
                    }

                    ctx.fillStyle = "rgba(255,255,255,0.9)";
                    for (const x of [x_rise, x_set]) {
                        ctx.beginPath();
                        ctx.arc(x, horizon, 3.5, 0, 2 * Math.PI);
                        ctx.fill();
                    }
                    ctx.restore();
                }

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                Connections {
                    target: root
                    function onDayChanged() { sky.requestPaint(); }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                radius: Style.radius(10)
                border.width: 1
                border.color: Style.frame_border_color
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                text: root.day ? Qt.formatDate(new Date(root.day.date + "T00:00:00"), "ddd d MMM") + "  ·  " + root.day_length() + " of daylight" : ""
                color: "#ffffff"
                opacity: 0.88
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
                font.weight: Font.DemiBold
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            StatTile {
                glyph: "\u{f059c}"
                glyph_color: "#f2b36b"
                label: "SUNRISE"
                value: root.day ? WeatherState.fmt_hm(root.day.sunrise) : ""
            }

            StatTile {
                glyph: "\u{f059b}"
                glyph_color: "#e8806b"
                label: "SUNSET"
                value: root.day ? WeatherState.fmt_hm(root.day.sunset) : ""
            }

            StatTile {
                glyph: "\u{f05a8}"
                glyph_color: Theme.theme_primary
                label: "DAYLIGHT"
                value: root.day_length()
            }
        }

        Modern.CardSurface {
            Layout.fillWidth: true
            implicitHeight: moon_row.implicitHeight + 20

            RowLayout {
                id: moon_row
                anchors.fill: parent
                anchors.margins: 10
                spacing: 12

                Item {
                    readonly property real size: Math.min(72, Math.max(48, root.width / 5))
                    Layout.preferredWidth: size
                    Layout.preferredHeight: size

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.92
                        height: width
                        radius: width / 2
                        color: Qt.alpha(Theme.theme_secondary, 0.12)
                    }

                    Image {
                        anchors.fill: parent
                        source: WeatherState.moon_icon_source(root.moon_phase)
                        sourceSize.width: 176
                        sourceSize.height: 176
                        smooth: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: WeatherState.moon_name(root.moon_phase)
                        color: Style.text_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(2)
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "Rises " + (root.moon_times.rise || "—") + (root.moon_times.set ? "   ·   Sets " + root.moon_times.set : "")
                        color: Style.text_dim
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                        font.features: { "tnum": 1 }
                    }

                    Rectangle {
                        implicitWidth: full_text.implicitWidth + 16
                        implicitHeight: full_text.implicitHeight + 6
                        radius: height / 2
                        color: Qt.alpha(Theme.theme_primary, 0.16)

                        Text {
                            id: full_text
                            anchors.centerIn: parent
                            text: "Next full moon " + root.next_full
                            color: Style.text_strong
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-3)
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }
}
