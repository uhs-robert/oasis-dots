pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.ui.frames
import qs.theme
import qs.services
import qs.styles.reticle.widgets

// A targeting scope on the sky: the selected day as a 24-hour range track, the sun an arc from sunrise to sunset with a lock on it when it is up today,
// the moon a dashed second arc with its phase drawn on the contact. Sunrise, sunset and the moon's data read out as HUD lines beneath.
Item {
    id: root

    property int day_cursor: 0
    property int first_day: 0
    property int day_span: 5
    property var on_select: function (i) {}

    readonly property color vec: Style.text_primary
    readonly property color vec_dim: Style.text_muted
    readonly property color lock: Style.selection_brackets.a > 0 ? Style.selection_brackets : Theme.theme_label
    readonly property var day: WeatherState.days[Math.max(0, Math.min(WeatherState.days.length - 1, root.day_cursor))]
    readonly property bool is_today: root.day_cursor === 0

    readonly property var moon_times: root.day ? WeatherState.moon_times_for_date(root.day.date) : ({ rise: null, set: null })
    readonly property real moon_phase: root.day ? WeatherState.moon_phase_for_date(root.day.date) : 0
    readonly property real moon_lit: (1 - Math.cos(2 * Math.PI * root.moon_phase)) / 2
    readonly property string next_full: root.day ? WeatherState.next_full_moon_label(root.day.date) : ""
    readonly property int days_to_full: Math.round((((0.5 - root.moon_phase) % 1 + 1) % 1) * WeatherState.lunar_cycle_days)

    readonly property int rise_min: root.clock_minutes(root.day ? root.day.sunrise : "")
    readonly property int set_min: root.clock_minutes(root.day ? root.day.sunset : "")
    readonly property bool has_sun: root.rise_min >= 0 && root.set_min > root.rise_min
    readonly property int moon_rise_min: root.clock_minutes(root.moon_times.rise)
    readonly property int moon_set_min: root.clock_minutes(root.moon_times.set)
    readonly property bool has_moon_track: root.moon_rise_min >= 0 && root.moon_set_min >= 0
    // Minutes the moon spends above the horizon, wrapping past midnight when it sets before it rises.
    readonly property int moon_span: root.moon_set_min >= root.moon_rise_min ? root.moon_set_min - root.moon_rise_min : root.moon_set_min + 1440 - root.moon_rise_min
    property int now_min: root.location_minutes()

    // The sun's position along today's daylight, or -1 outside daylight and on other days.
    readonly property real sun_fraction: root.is_today && root.has_sun && root.now_min >= root.rise_min && root.now_min <= root.set_min ? (root.now_min - root.rise_min) / (root.set_min - root.rise_min) : -1
    // The moon's position along its pass: live today while it is up, else the transit point.
    readonly property real moon_fraction: {
        if (!root.has_moon_track) return 0.5;
        if (!root.is_today) return 0.5;
        const since_rise = (root.now_min - root.moon_rise_min + 1440) % 1440;
        return since_rise <= root.moon_span ? since_rise / root.moon_span : 0.5;
    }

    // Both "7:09" (stored) and "7:09am" / "19:09" (clock-formatted) shapes.
    function clock_minutes(text) {
        const m = /^(\d{1,2}):(\d{2})\s*([ap]m)?$/i.exec(text || "");
        if (!m) return -1;
        let h = parseInt(m[1], 10);
        if (m[3]) h = h % 12 + (m[3].toLowerCase() === "pm" ? 12 : 0);
        return h * 60 + parseInt(m[2], 10);
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

    Timer {
        interval: 60000
        running: root.is_today
        repeat: true
        // Returning to today must not show the minute the view was last on until the next tick.
        triggeredOnStart: true
        onTriggered: root.now_min = root.location_minutes()
    }

    component Readout: RowLayout {
        id: readout
        property string label: ""
        property string value: ""
        property color value_color: Style.text_strong
        spacing: 5

        Text {
            text: readout.label
            color: root.vec_dim
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
            font.letterSpacing: 1.2
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            clip: true
            text: ".".repeat(80)
            color: Qt.alpha(root.vec, 0.25)
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
        }

        Text {
            Layout.maximumWidth: readout.width * 0.62
            elide: Text.ElideRight
            text: readout.value || "--"
            color: readout.value_color
            font.family: Style.number_font
            font.pixelSize: Style.fs(-2)
            font.bold: true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

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
                    implicitHeight: 22

                    Rectangle {
                        anchors.fill: parent
                        color: day_cell.open ? Style.selection_bg : "transparent"
                        border.width: day_cell.open ? 0 : 1
                        border.color: Qt.alpha(root.vec, 0.2)
                    }

                    LockBrackets {
                        shown: day_cell.open
                    }

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 4
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: (day_cell.width >= 60 ? day_cell.modelData.weekday : Qt.formatDate(new Date(day_cell.modelData.date + "T00:00:00"), "ddd")).toUpperCase()
                        color: day_cell.open ? root.lock : root.vec_dim
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-4)
                        font.bold: day_cell.open
                        font.letterSpacing: 1.2
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(day_cell.day_index)
                    }
                }
            }
        }

        Item {
            id: sky
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 110

            readonly property real pad: 16
            readonly property real span_w: sky.width - 2 * sky.pad
            readonly property real horizon_y: sky.height - 22
            readonly property real arc_h: Math.max(40, sky.horizon_y - 34)
            readonly property real sun_x: root.has_sun ? sky.x_of(root.rise_min + (root.set_min - root.rise_min) * root.sun_fraction) : 0
            readonly property real sun_y: sky.horizon_y - Math.sin(Math.PI * root.sun_fraction) * sky.arc_h
            readonly property real ghost_x: root.has_sun ? sky.x_of((root.rise_min + root.set_min) / 2) : sky.width / 2
            readonly property real moon_arc_h: sky.arc_h * 0.7
            readonly property real moon_x: root.has_moon_track ? sky.x_of((root.moon_rise_min + root.moon_fraction * root.moon_span) % 1440) : 0
            readonly property real moon_y: sky.horizon_y - Math.sin(Math.PI * root.moon_fraction) * sky.moon_arc_h
            readonly property real moon_r: 9

            function x_of(minutes) {
                return sky.pad + minutes / 1440 * sky.span_w;
            }

            Canvas {
                id: sky_canvas
                anchors.fill: parent

                function disc(ctx, cx, cy, r) {
                    ctx.strokeStyle = root.vec;
                    ctx.lineWidth = 1.2;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                    ctx.stroke();
                    // Lit limb along one side, the terminator an ellipse of the same height back the other way.
                    const waxing = root.moon_phase < 0.5;
                    const c = Math.cos(2 * Math.PI * root.moon_phase);
                    ctx.fillStyle = root.vec;
                    ctx.beginPath();
                    const steps = 24;
                    for (let i = 0; i <= steps; i++) {
                        const a = -Math.PI / 2 + Math.PI * i / steps;
                        const x = cx + (waxing ? 1 : -1) * r * Math.cos(a);
                        if (i === 0) ctx.moveTo(x, cy + r * Math.sin(a)); else ctx.lineTo(x, cy + r * Math.sin(a));
                    }
                    for (let i = steps; i >= 0; i--) {
                        const a = -Math.PI / 2 + Math.PI * i / steps;
                        ctx.lineTo(cx + (waxing ? 1 : -1) * c * r * Math.cos(a), cy + r * Math.sin(a));
                    }
                    ctx.closePath();
                    ctx.fill();
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const w = width;
                    const hy = sky.horizon_y;

                    // Range scale on the horizon: a tick per hour, long every six with its hour figure.
                    ctx.strokeStyle = root.vec;
                    ctx.lineWidth = 1;
                    ctx.globalAlpha = 0.35;
                    ctx.beginPath();
                    ctx.moveTo(sky.pad, hy + 0.5);
                    ctx.lineTo(w - sky.pad, hy + 0.5);
                    ctx.stroke();
                    ctx.globalAlpha = 0.8;
                    for (let h = 0; h <= 24; h++) {
                        const x = Math.round(sky.x_of(h * 60)) + 0.5;
                        ctx.beginPath();
                        ctx.moveTo(x, hy);
                        ctx.lineTo(x, hy + (h % 6 === 0 ? 8 : h % 3 === 0 ? 5 : 3));
                        ctx.stroke();
                    }
                    ctx.globalAlpha = 1;
                    ctx.fillStyle = root.vec_dim;
                    ctx.font = Style.fs(-5) + "px \"" + Style.font_family + "\"";
                    ctx.textAlign = "center";
                    for (let h = 0; h <= 24; h += 6) ctx.fillText(TimeFormat.hour(new Date(2000, 0, 1, h % 24)), sky.x_of(h * 60), hy + 20);

                    // Altitude rings on the track: half and full height of the sun's arc.
                    ctx.setLineDash([2, 4]);
                    ctx.globalAlpha = 0.25;
                    for (const f of [0.5, 1]) {
                        ctx.beginPath();
                        ctx.moveTo(sky.pad, hy - sky.arc_h * f);
                        ctx.lineTo(w - sky.pad, hy - sky.arc_h * f);
                        ctx.stroke();
                    }
                    ctx.setLineDash([]);
                    ctx.globalAlpha = 1;

                    // Noon meridian.
                    ctx.strokeStyle = root.vec;
                    ctx.globalAlpha = 0.18;
                    ctx.beginPath();
                    ctx.moveTo(sky.x_of(720) + 0.5, hy - sky.arc_h - 6);
                    ctx.lineTo(sky.x_of(720) + 0.5, hy);
                    ctx.stroke();
                    ctx.globalAlpha = 1;

                    if (root.has_moon_track) {
                        ctx.setLineDash([3, 3]);
                        ctx.strokeStyle = root.vec_dim;
                        ctx.lineWidth = 1.2;
                        ctx.beginPath();
                        let wrapped_from = -1;
                        for (let i = 0; i <= 48; i++) {
                            const t = i / 48;
                            const minute = (root.moon_rise_min + t * root.moon_span) % 1440;
                            const x = sky.x_of(minute), y = hy - Math.sin(Math.PI * t) * sky.moon_arc_h;
                            if (i === 0 || minute < wrapped_from) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                            wrapped_from = minute;
                        }
                        ctx.stroke();
                        ctx.setLineDash([]);
                    }

                    if (root.has_sun) {
                        ctx.strokeStyle = root.vec;
                        ctx.lineWidth = 1.6;
                        ctx.beginPath();
                        for (let i = 0; i <= 60; i++) {
                            const t = i / 60;
                            const x = sky.x_of(root.rise_min + (root.set_min - root.rise_min) * t), y = hy - Math.sin(Math.PI * t) * sky.arc_h;
                            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                        }
                        ctx.stroke();

                        // Sunrise and sunset on the horizon as notches with their times.
                        ctx.fillStyle = root.vec;
                        ctx.font = "bold " + Style.fs(-4) + "px \"" + Style.number_font + "\"";
                        const rise_x = sky.x_of(root.rise_min), set_x = sky.x_of(root.set_min);
                        ctx.fillRect(rise_x - 1, hy - 7, 2, 7);
                        ctx.fillRect(set_x - 1, hy - 7, 2, 7);
                        ctx.textAlign = "right";
                        ctx.fillText(WeatherState.fmt_hm(root.day.sunrise), rise_x - 5, hy - 3);
                        ctx.textAlign = "left";
                        ctx.fillText(WeatherState.fmt_hm(root.day.sunset), set_x + 5, hy - 3);
                    }

                    if (root.has_moon_track) sky_canvas.disc(ctx, sky.moon_x, sky.moon_y, sky.moon_r - 1);
                }

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                Connections {
                    target: root
                    function onDayChanged() { sky_canvas.requestPaint(); }
                    function onNow_minChanged() { sky_canvas.requestPaint(); }
                }
                Connections {
                    target: TimeFormat
                    function onH24Changed() { sky_canvas.requestPaint(); }
                }
                Connections {
                    target: Style
                    function onFont_familyChanged() { sky_canvas.requestPaint(); }
                    function onFont_sizeChanged() { sky_canvas.requestPaint(); }
                    function onPalChanged() { sky_canvas.requestPaint(); }
                    function onText_primaryChanged() { sky_canvas.requestPaint(); }
                    function onText_mutedChanged() { sky_canvas.requestPaint(); }
                }
            }

            Item {
                id: sun_lock
                visible: root.sun_fraction >= 0
                x: sky.sun_x - 15
                y: sky.sun_y - 15
                width: 30
                height: 30

                Reticle {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    color: root.lock
                    center_color: root.lock
                }

                CornerBrackets {
                    anchors.fill: parent
                    color: root.lock
                    inset: sun_lock.gap
                    arm: 6
                    thickness: 1.5
                    all_corners: true
                }

                property real gap: 0

                SequentialAnimation on gap {
                    running: sun_lock.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: 3; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 3; to: 0; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            Text {
                visible: sun_lock.visible
                x: Math.min(sky.width - width - 4, sky.sun_x + 20)
                y: sky.sun_y - height / 2
                text: "SOL " + Math.round(root.sun_fraction * 100) + "%"
                color: root.lock
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.bold: true
                font.letterSpacing: 1
            }

            // Without a live sun the arc's peak carries a dim diamond, so the track still reads as a tracked contact.
            Rectangle {
                visible: !sun_lock.visible && root.has_sun
                x: sky.ghost_x - 4
                y: sky.horizon_y - sky.arc_h - 4
                width: 8
                height: 8
                rotation: 45
                color: "transparent"
                border.width: 1
                border.color: root.vec
            }

            Text {
                x: 4
                y: 0
                text: root.day ? root.day.date.substr(5).replace("-", " / ") + " · " + (root.is_today ? "LIVE" : "FORECAST") : ""
                color: root.vec_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 1.5
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 4
                y: 0
                text: "TRACK " + root.day_length()
                color: root.vec
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.bold: true
                font.letterSpacing: 1.5
            }

            Text {
                visible: root.has_moon_track
                x: Math.min(sky.width - width - 4, sky.moon_x + 16)
                y: sky.moon_y - height / 2
                text: "LUN " + Math.round(root.moon_lit * 100) + "%"
                color: root.vec_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 1
            }

            Item {
                visible: root.has_moon_track
                x: sky.moon_x - 12
                y: sky.moon_y - 12
                width: 24
                height: 24

                CornerBrackets {
                    anchors.fill: parent
                    color: root.vec_dim
                    inset: 2
                    arm: 4
                    all_corners: true
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.alpha(root.vec, 0.3)
        }

        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 340 ? 2 : 1
            columnSpacing: 16
            rowSpacing: 3

            Readout { Layout.fillWidth: true; Layout.preferredWidth: 1; label: "SUNRISE"; value: root.day ? WeatherState.fmt_hm(root.day.sunrise) : "" }
            Readout { Layout.fillWidth: true; Layout.preferredWidth: 1; label: "MOONRISE"; value: root.moon_times.rise || "" }
            Readout { Layout.fillWidth: true; Layout.preferredWidth: 1; label: "SUNSET"; value: root.day ? WeatherState.fmt_hm(root.day.sunset) : "" }
            Readout { Layout.fillWidth: true; Layout.preferredWidth: 1; label: "MOONSET"; value: root.moon_times.set || "" }
            Readout { Layout.fillWidth: true; Layout.preferredWidth: 1; label: "DAY LENGTH"; value: root.day_length() }
            Readout { Layout.fillWidth: true; Layout.preferredWidth: 1; label: "PHASE"; value: WeatherState.moon_name(root.moon_phase); value_color: root.vec }
            Readout { Layout.fillWidth: true; Layout.preferredWidth: 1; visible: root.width >= 340; label: "SOL"; value: root.sun_fraction >= 0 ? "LOCKED " + Math.round(root.sun_fraction * 100) + "%" : root.is_today ? (root.now_min < root.rise_min ? "BELOW" : "SET") : "NO LOCK"; value_color: root.sun_fraction >= 0 ? root.lock : Style.text_strong }
            Readout { Layout.fillWidth: true; Layout.preferredWidth: 1; label: "NEXT FULL"; value: root.next_full + " · " + root.days_to_full + "D" }
        }
    }
}
