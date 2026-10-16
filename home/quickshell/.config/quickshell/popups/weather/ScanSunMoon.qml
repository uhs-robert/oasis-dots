import QtQuick
import QtQuick.Layouts
import qs.components
import qs.theme
import qs.services

// A Scan Visor logbook entry, "Celestial bodies": the selected day as the sun's orbit with its rise and set nodes, the moon scanned beside it,
// then the sky events as data rows, under the Daily day window as a visor strip.
Item {
    id: root

    property int day_cursor: 0
    property int first_day: 0
    property int day_span: 5
    property var on_select: function (i) {}

    readonly property color visor: Style.pal.primary
    readonly property color visor_light: Style.pal.primary_light
    readonly property bool shown: root.visible && Popups.open_name === "weather"

    readonly property var day: WeatherState.days[Math.max(0, Math.min(WeatherState.days.length - 1, root.day_cursor))]
    readonly property bool is_today: root.day_cursor === 0

    readonly property var moon_times: root.day ? WeatherState.moon_times_for_date(root.day.date) : ({ rise: null, set: null })
    readonly property real moon_phase: root.day ? WeatherState.moon_phase_for_date(root.day.date) : 0
    readonly property real moon_lit: (1 - Math.cos(2 * Math.PI * root.moon_phase)) / 2
    readonly property string next_full: root.day ? WeatherState.next_full_moon_label(root.day.date) : ""

    readonly property int rise_min: root.hm_minutes(root.day ? root.day.sunrise : "")
    readonly property int set_min: root.hm_minutes(root.day ? root.day.sunset : "")
    readonly property bool has_sun: root.rise_min >= 0 && root.set_min > root.rise_min
    property int now_min: root.location_minutes()

    function hm_minutes(hm) {
        const parts = (hm || "").split(":");
        return parts.length === 2 ? parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10) : -1;
    }

    function location_minutes() {
        const loc = WeatherState.location_now();
        return loc.getUTCHours() * 60 + loc.getUTCMinutes();
    }

    function day_length() {
        if (!root.has_sun) return "--";
        const mins = root.set_min - root.rise_min;
        return Math.floor(mins / 60) + "H " + (mins % 60) + "M";
    }

    function moon_event(time, always_up, always_down) {
        return time || (always_up ? "ALWAYS UP" : always_down ? "BELOW HORIZON" : "--");
    }

    Timer {
        interval: 60000
        running: root.is_today && root.shown
        repeat: true
        onTriggered: root.now_min = root.location_minutes()
    }

    component LogRow: Item {
        id: log_row
        property string label: ""
        property string value: ""

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: Math.max(label_text.implicitHeight, value_text.implicitHeight) + 5

        Text {
            id: label_text
            anchors.left: parent.left
            anchors.baseline: value_text.baseline
            text: log_row.label
            color: root.visor
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
            font.letterSpacing: 2
        }

        Text {
            id: value_text
            anchors.left: label_text.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.top: parent.top
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: log_row.value
            color: Style.pal.fg_strong
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.alpha(root.visor, 0.4) }
                GradientStop { position: 1; color: Qt.alpha(root.visor, 0.05) }
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
                    readonly property bool open: day_cell.day_index === root.day_cursor

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: 26

                    Rectangle {
                        anchors.fill: parent
                        color: Qt.alpha(root.visor, day_cell.open ? 0.1 : 0.03)
                    }

                    ScanLock {
                        visible: day_cell.open
                        shown: day_cell.open && root.shown
                    }

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 6
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: (day_cell.width >= 60 ? day_cell.modelData.weekday : Qt.formatDate(new Date(day_cell.modelData.date + "T00:00:00"), "ddd")).toUpperCase()
                        color: day_cell.open ? root.visor_light : Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-4)
                        font.letterSpacing: day_cell.width >= 50 ? 1.5 : 0
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(day_cell.day_index)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "LOGBOOK"
                color: root.visor
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 2.5
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: "CELESTIAL BODIES"
                color: Style.pal.fg_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 2.5
            }

            Text {
                text: root.day ? root.day.date.substr(5).replace("-", ".") : ""
                color: Style.text_muted
                font.family: Style.number_font
                font.pixelSize: Style.fs(-5)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: -4
            Layout.preferredHeight: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.alpha(root.visor, 0.6) }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 100
            spacing: 10

            // The day as a ring seen edge-on: the horizon cuts it where the sun rises and sets, so a long day shows more arc above the line.
            Canvas {
                id: orbit
                Layout.fillWidth: true
                Layout.fillHeight: true

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                Connections {
                    target: root
                    function onDayChanged() { orbit.requestPaint(); }
                    function onNow_minChanged() { orbit.requestPaint(); }
                }

                Connections {
                    target: Style
                    function onPalChanged() { orbit.requestPaint(); }
                    function onFont_familyChanged() { orbit.requestPaint(); }
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const w = width, h = height;
                    const cx = w / 2, cy = h / 2;
                    const rx = Math.max(20, w / 2 - 22), ry = Math.max(14, Math.min(h / 2 - 10, rx * 0.6));
                    const frac = root.has_sun ? (root.set_min - root.rise_min) / 1440 : 0.5;
                    const half = Math.PI * frac;
                    const horizon_y = cy - ry * Math.cos(half);
                    const node_dx = rx * Math.sin(half);
                    const pt = phi => ({ x: cx + rx * Math.sin(phi), y: cy - ry * Math.cos(phi) });

                    const ring = (from, to, steps) => {
                        ctx.beginPath();
                        for (let i = 0; i <= steps; i++) {
                            const p = pt(from + (to - from) * i / steps);
                            if (i === 0) ctx.moveTo(p.x, p.y); else ctx.lineTo(p.x, p.y);
                        }
                    };

                    ctx.fillStyle = root.visor;
                    ctx.globalAlpha = 0.08;
                    ring(-half, half, 48);
                    ctx.closePath();
                    ctx.fill();
                    ctx.globalAlpha = 1;

                    // Hour ticks around the ring, noon at the top.
                    ctx.strokeStyle = root.visor_light;
                    ctx.lineWidth = 1;
                    for (let i = 0; i < 24; i++) {
                        const phi = i * Math.PI / 12;
                        const inner = { x: cx + (rx - 4) * Math.sin(phi), y: cy - (ry - 4 * ry / rx) * Math.cos(phi) };
                        const outer = pt(phi);
                        ctx.globalAlpha = i % 6 === 0 ? 0.7 : 0.3;
                        ctx.beginPath();
                        ctx.moveTo(inner.x, inner.y);
                        ctx.lineTo(outer.x, outer.y);
                        ctx.stroke();
                    }
                    ctx.globalAlpha = 1;

                    ctx.strokeStyle = Style.text_muted;
                    ctx.lineWidth = 1.2;
                    ctx.setLineDash([3, 3]);
                    ring(half, 2 * Math.PI - half, 48);
                    ctx.stroke();
                    ctx.setLineDash([]);

                    ctx.strokeStyle = root.visor_light;
                    for (const pass of [[6, 0.1], [3, 0.2], [1.5, 1]]) {
                        ctx.lineWidth = pass[0];
                        ctx.globalAlpha = pass[1];
                        ring(-half, half, 48);
                        ctx.stroke();
                    }
                    ctx.globalAlpha = 1;

                    ctx.strokeStyle = root.visor;
                    ctx.globalAlpha = 0.55;
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(0, Math.round(horizon_y) + 0.5);
                    ctx.lineTo(w, Math.round(horizon_y) + 0.5);
                    ctx.stroke();
                    ctx.globalAlpha = 1;

                    if (!root.has_sun) return;

                    ctx.font = Style.fs(-5) + "px \"" + Style.font_family + "\"";
                    ctx.textAlign = "center";
                    for (const node of [{ x: cx - node_dx, tag: "RISE" }, { x: cx + node_dx, tag: "SET" }]) {
                        ctx.fillStyle = root.visor_light;
                        ctx.beginPath();
                        ctx.moveTo(node.x, horizon_y - 5);
                        ctx.lineTo(node.x + 5, horizon_y);
                        ctx.lineTo(node.x, horizon_y + 5);
                        ctx.lineTo(node.x - 5, horizon_y);
                        ctx.closePath();
                        ctx.fill();
                        ctx.fillStyle = Style.text_muted;
                        ctx.fillText(node.tag, node.x, horizon_y + 17);
                    }

                    ctx.fillStyle = Style.pal.fg_strong;
                    ctx.font = Style.fs(-3) + "px \"" + Style.number_font + "\"";
                    ctx.fillText(root.day_length(), cx, horizon_y - 8);

                    if (!root.is_today) return;
                    const noon = (root.rise_min + root.set_min) / 2;
                    let phi = 2 * Math.PI * (root.now_min - noon) / 1440;
                    phi = Math.atan2(Math.sin(phi), Math.cos(phi));
                    const sun = pt(phi);
                    const up = sun.y < horizon_y;
                    ctx.strokeStyle = up ? Style.pal.yellow : Style.text_muted;
                    ctx.fillStyle = up ? Style.pal.yellow : Style.text_muted;
                    ctx.globalAlpha = 0.3;
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.arc(sun.x, sun.y, 10, 0, 2 * Math.PI);
                    ctx.stroke();
                    ctx.globalAlpha = 1;
                    ctx.beginPath();
                    ctx.arc(sun.x, sun.y, 5, 0, 2 * Math.PI);
                    if (up) ctx.fill(); else ctx.stroke();
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: false
                Layout.preferredWidth: moon_box.size
                Layout.maximumWidth: moon_box.size
                spacing: 4

                Item {
                    id: moon_box
                    readonly property real size: Math.max(64, Math.min(96, root.width / 4))
                    Layout.preferredWidth: size
                    Layout.preferredHeight: size

                    Canvas {
                        id: moon
                        anchors.fill: parent
                        anchors.margins: 8

                        onWidthChanged: requestPaint()

                        Connections {
                            target: root
                            function onMoon_phaseChanged() { moon.requestPaint(); }
                        }

                        Connections {
                            target: Style
                            function onPalChanged() { moon.requestPaint(); }
                        }

                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const r = width / 2, cx = r, cy = r;
                            const phase = root.moon_phase;
                            const waxing = phase < 0.5;
                            const k = Math.cos(2 * Math.PI * phase);
                            const side = waxing ? 1 : -1;

                            ctx.beginPath();
                            ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                            ctx.fillStyle = root.visor;
                            ctx.globalAlpha = 0.08;
                            ctx.fill();

                            // Lit part: the limb on the lit side, closed by the terminator ellipse (a flat line at the quarters).
                            ctx.globalAlpha = 0.55;
                            ctx.fillStyle = root.visor_light;
                            ctx.beginPath();
                            const steps = 32;
                            for (let i = 0; i <= steps; i++) {
                                const t = Math.PI * i / steps;
                                const x = cx + side * r * Math.sin(t), y = cy - r * Math.cos(t);
                                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                            }
                            for (let i = steps; i >= 0; i--) {
                                const t = Math.PI * i / steps;
                                ctx.lineTo(cx + side * r * k * Math.sin(t), cy - r * Math.cos(t));
                            }
                            ctx.closePath();
                            ctx.fill();

                            // Scan wireframe: meridians and parallels across the disc.
                            ctx.save();
                            ctx.beginPath();
                            ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                            ctx.clip();
                            ctx.strokeStyle = root.visor_light;
                            ctx.globalAlpha = 0.3;
                            ctx.lineWidth = 1;
                            for (const m of [0.35, 0.7]) {
                                ctx.beginPath();
                                ctx.ellipse(cx - r * m, cy - r, 2 * r * m, 2 * r);
                                ctx.stroke();
                            }
                            for (const p of [-0.5, 0, 0.5]) {
                                ctx.beginPath();
                                ctx.moveTo(0, cy + r * p);
                                ctx.lineTo(2 * r, cy + r * p);
                                ctx.stroke();
                            }
                            ctx.restore();

                            ctx.globalAlpha = 0.9;
                            ctx.strokeStyle = root.visor_light;
                            ctx.lineWidth = 1.2;
                            ctx.beginPath();
                            ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                            ctx.stroke();
                        }

                        Item {
                            anchors.fill: parent
                            clip: true

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: Qt.alpha(root.visor_light, 0.6)

                                NumberAnimation on y {
                                    running: root.shown
                                    loops: Animation.Infinite
                                    from: 0
                                    to: moon.height
                                    duration: 2400
                                }
                            }
                        }
                    }

                    CornerBrackets {
                        anchors.fill: parent
                        color: Qt.alpha(root.visor, 0.7)
                        inset: 0
                        arm: 7
                        thickness: 1.5
                        all_corners: true
                    }
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: "ILLUM " + Math.round(root.moon_lit * 100) + "%"
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                    font.letterSpacing: 1.5
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 340 ? 2 : 1
            columnSpacing: 14
            rowSpacing: 0

            LogRow { label: "SUNRISE"; value: root.day ? WeatherState.fmt_hm(root.day.sunrise) || "--" : "--" }
            LogRow { label: "MOONRISE"; value: root.moon_event(root.moon_times.rise, root.moon_times.always_up, false).toUpperCase() }
            LogRow { label: "SUNSET"; value: root.day ? WeatherState.fmt_hm(root.day.sunset) || "--" : "--" }
            LogRow { label: "MOONSET"; value: root.moon_event(root.moon_times.set, false, root.moon_times.always_down).toUpperCase() }
            LogRow { label: "DAY LENGTH"; value: root.day_length() }
            LogRow { label: "NEXT FULL MOON"; value: root.next_full.toUpperCase() }
            LogRow {
                Layout.columnSpan: root.width >= 340 ? 2 : 1
                label: "LUNAR PHASE"
                value: WeatherState.moon_name(root.moon_phase).toUpperCase()
            }
        }
    }
}
