pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.styles.reticle.widgets

// The selected day as two concentric rings under the Daily day strip: a 24 hour dial whose lit segment runs sunrise to sunset
// (today adds the sun's live position), and inside it the moon's illumination as a gauge with the phase marked on it.
Item {
    id: root

    property int day_cursor: 0
    property int first_day: 0
    property int day_span: 5
    property var on_select: function (i) {}

    readonly property color ink: Style.text_strong
    readonly property color accent: Style.text_primary
    readonly property bool shown: root.visible && Popups.open_name === "weather"

    readonly property var day: WeatherState.days[Math.max(0, Math.min(WeatherState.days.length - 1, root.day_cursor))]
    readonly property bool is_today: root.day_cursor === 0

    readonly property var moon_times: root.day ? WeatherState.moon_times_for_date(root.day.date) : ({ rise: null, set: null, always_up: false, always_down: false })
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
        if (!root.has_sun) return "—";
        const mins = root.set_min - root.rise_min;
        return Math.floor(mins / 60) + "h " + (mins % 60) + "m";
    }

    function moon_event(time) {
        return time || (root.moon_times.always_up ? "Always up" : root.moon_times.always_down ? "Below horizon" : "—");
    }

    Timer {
        interval: 60000
        running: root.is_today && root.shown
        repeat: true
        onTriggered: root.now_min = root.location_minutes()
    }

    component Readout: ColumnLayout {
        id: readout
        property string label: ""
        property string value: ""
        property bool align_right: false

        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 1

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            horizontalAlignment: readout.align_right ? Text.AlignRight : Text.AlignLeft
            elide: Text.ElideRight
            text: readout.label
            color: Style.text_muted
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.5
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            horizontalAlignment: readout.align_right ? Text.AlignRight : Text.AlignLeft
            elide: Text.ElideRight
            text: readout.value
            color: Style.text_strong
            font.family: Style.font_family
            font.pixelSize: Style.fs(-1)
            font.letterSpacing: 0.5
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
                        color: day_cell.open ? Style.selection_bg : "transparent"
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: day_cell.open ? Style.text_strong : Style.hairline_dim
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 4

                        Reticle {
                            visible: day_cell.open && day_cell.width >= 56
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            color: root.accent
                            center_color: root.accent
                        }

                        Text {
                            width: Math.min(implicitWidth, day_cell.width - 6)
                            elide: Text.ElideRight
                            text: (day_cell.width >= 60 ? day_cell.modelData.weekday : Qt.formatDate(new Date(day_cell.modelData.date + "T00:00:00"), "ddd")).toUpperCase()
                            color: day_cell.open ? Style.text_strong : Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                            font.letterSpacing: day_cell.width >= 50 ? 1.5 : 0
                        }
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
                text: "CELESTIAL"
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 2.5
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Style.hairline }
                    GradientStop { position: 1; color: "transparent" }
                }
            }

            Text {
                text: root.day ? root.day.date.substr(5).replace("-", ".") : ""
                color: Style.text_strong
                font.family: Style.number_font
                font.pixelSize: Style.fs(-3)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 120
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignVCenter
                spacing: 10

                Readout { label: "Sunrise"; value: root.day ? WeatherState.fmt_hm(root.day.sunrise) || "—" : "—" }
                Readout { label: "Sunset"; value: root.day ? WeatherState.fmt_hm(root.day.sunset) || "—" : "—" }
                Readout { label: "Day length"; value: root.day_length() }
            }

            Canvas {
                id: dial
                Layout.preferredWidth: Math.max(100, Math.min(height, 224, root.width - 170))
                Layout.fillHeight: true

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                Connections {
                    target: root
                    function onDayChanged() { dial.requestPaint(); }
                    function onNow_minChanged() { dial.requestPaint(); }
                }

                Connections {
                    target: TimeFormat
                    function onH24Changed() { dial.requestPaint(); }
                }

                Connections {
                    target: Style
                    function onPalChanged() { dial.requestPaint(); }
                    function onFont_familyChanged() { dial.requestPaint(); }
                    function onText_strongChanged() { dial.requestPaint(); }
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const size = Math.min(width, height, 260);
                    const cx = width / 2, cy = height / 2;
                    const outer = size / 2 - 32;
                    const inner = outer - Math.max(20, size * 0.13);
                    const disc = inner - 12;
                    const tau = Math.PI * 2;
                    // Clock minutes to dial angle: noon at the top, midnight at the bottom, time running clockwise.
                    const angle_of = m => (m - 720) / 1440 * tau - Math.PI / 2;
                    const at = (a, r) => ({ x: cx + r * Math.cos(a), y: cy + r * Math.sin(a) });
                    const line = (a, r1, r2) => {
                        const p = at(a, r1), q = at(a, r2);
                        ctx.beginPath();
                        ctx.moveTo(p.x, p.y);
                        ctx.lineTo(q.x, q.y);
                        ctx.stroke();
                    };

                    ctx.lineWidth = 1;
                    ctx.strokeStyle = Style.text_muted;
                    ctx.globalAlpha = 0.3;
                    ctx.beginPath();
                    ctx.arc(cx, cy, outer, 0, tau);
                    ctx.stroke();
                    ctx.beginPath();
                    ctx.arc(cx, cy, inner, 0, tau);
                    ctx.stroke();

                    // Hour ticks outside the dial, a longer one every six hours and its label beyond.
                    ctx.strokeStyle = root.ink;
                    for (let i = 0; i < 24; i++) {
                        const major = i % 6 === 0;
                        ctx.globalAlpha = major ? 0.7 : 0.3;
                        line(angle_of(i * 60), outer + 4, outer + (major ? 9 : 6));
                    }
                    ctx.globalAlpha = 1;
                    ctx.fillStyle = Style.text_muted;
                    ctx.font = Style.fs(-5) + "px \"" + Style.number_font + "\"";
                    ctx.textAlign = "center";
                    ctx.textBaseline = "middle";
                    for (const h of [0, 6, 12, 18]) {
                        const text = TimeFormat.hour(new Date(2000, 0, 1, h));
                        // The side numerals are wide, so their centres sit further out than the top and bottom ones to clear the ticks.
                        const reach = h % 12 === 0 ? 17 : 12 + ctx.measureText(text).width / 2;
                        const p = at(angle_of(h * 60), outer + reach);
                        ctx.fillText(text, p.x, p.y);
                    }

                    if (root.has_sun) {
                        // Daylight: the segment between sunrise and sunset, with a tick across the ring at each end.
                        ctx.strokeStyle = root.ink;
                        ctx.lineWidth = 3;
                        ctx.beginPath();
                        ctx.arc(cx, cy, outer, angle_of(root.rise_min), angle_of(root.set_min), false);
                        ctx.stroke();
                        ctx.lineWidth = 1.5;
                        line(angle_of(root.rise_min), outer - 7, outer + 7);
                        line(angle_of(root.set_min), outer - 7, outer + 7);

                        if (root.is_today) {
                            const up = root.now_min >= root.rise_min && root.now_min <= root.set_min;
                            const p = at(angle_of(root.now_min), outer);
                            ctx.fillStyle = Style.frame_color;
                            ctx.strokeStyle = root.ink;
                            ctx.lineWidth = 1.2;
                            ctx.globalAlpha = 0.4;
                            ctx.beginPath();
                            ctx.arc(p.x, p.y, 9, 0, tau);
                            ctx.stroke();
                            ctx.globalAlpha = 1;
                            ctx.beginPath();
                            ctx.arc(p.x, p.y, 5, 0, tau);
                            if (up) {
                                ctx.fillStyle = root.ink;
                                ctx.fill();
                            } else {
                                ctx.fill();
                                ctx.stroke();
                            }
                        }
                    }

                    // Moon: the illuminated fraction lit clockwise from the top, with a diamond where the phase sits in the month.
                    ctx.strokeStyle = root.ink;
                    ctx.lineWidth = 2.5;
                    ctx.beginPath();
                    ctx.arc(cx, cy, inner, -Math.PI / 2, -Math.PI / 2 + tau * root.moon_lit, false);
                    if (root.moon_lit > 0.002) ctx.stroke();
                    const mark = at(-Math.PI / 2 + tau * root.moon_phase, inner);
                    ctx.fillStyle = root.accent;
                    ctx.strokeStyle = Style.frame_color;
                    ctx.lineWidth = 1.5;
                    ctx.beginPath();
                    ctx.moveTo(mark.x, mark.y - 5);
                    ctx.lineTo(mark.x + 5, mark.y);
                    ctx.lineTo(mark.x, mark.y + 5);
                    ctx.lineTo(mark.x - 5, mark.y);
                    ctx.closePath();
                    ctx.stroke();
                    ctx.fill();

                    // The disc itself: lit limb on the lit side, closed by the terminator (a flat line at the quarters).
                    const k = Math.cos(tau * root.moon_phase);
                    const side = root.moon_phase < 0.5 ? 1 : -1;
                    const steps = 32;
                    ctx.beginPath();
                    ctx.arc(cx, cy, disc, 0, tau);
                    ctx.strokeStyle = root.ink;
                    ctx.globalAlpha = 0.5;
                    ctx.lineWidth = 1;
                    ctx.stroke();
                    ctx.globalAlpha = 0.7;
                    ctx.fillStyle = root.ink;
                    ctx.beginPath();
                    for (let i = 0; i <= steps; i++) {
                        const t = Math.PI * i / steps;
                        const x = cx + side * disc * Math.sin(t), y = cy - disc * Math.cos(t);
                        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                    }
                    for (let i = steps; i >= 0; i--) {
                        const t = Math.PI * i / steps;
                        ctx.lineTo(cx + side * disc * k * Math.sin(t), cy - disc * Math.cos(t));
                    }
                    ctx.closePath();
                    ctx.fill();
                    ctx.globalAlpha = 1;
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignVCenter
                spacing: 10

                Readout { label: "Moonrise"; value: root.moon_event(root.moon_times.rise); align_right: true }
                Readout { label: "Moonset"; value: root.moon_event(root.moon_times.set); align_right: true }
                Readout { label: "Next full"; value: root.next_full || "—"; align_right: true }
            }
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: WeatherState.moon_name(root.moon_phase).toUpperCase() + " · " + Math.round(root.moon_lit * 100) + "%"
            color: Style.text_strong
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
            font.letterSpacing: 2.5
        }
    }
}
