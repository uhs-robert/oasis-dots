// home/quickshell/.config/quickshell/popups/weather/SunMoonView.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// Sun arc for the selected day (today shows the current-position dot), plus moon phase,
// moonrise/moonset and the next full moon date. h/l move the selected-day cursor.
Item {
    id: root

    property int day_cursor: 0

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

    function sun_fraction() {
        if (!root.is_today) return null;
        const rise = root.hm_minutes(root.day ? root.day.sunrise : "");
        const set = root.hm_minutes(root.day ? root.day.sunset : "");
        if (rise === null || set === null || set <= rise) return null;
        const loc = WeatherState.location_now();
        const now = loc.getUTCHours() * 60 + loc.getUTCMinutes();
        if (now < rise || now > set) return null;
        return (now - rise) / (set - rise);
    }

    function day_length() {
        const rise = root.hm_minutes(root.day ? root.day.sunrise : "");
        const set = root.hm_minutes(root.day ? root.day.sunset : "");
        if (rise === null || set === null || set <= rise) return "—";
        const mins = set - rise;
        return Math.floor(mins / 60) + "h " + (mins % 60) + "m";
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Repeater {
                model: [{ icon: WeatherState.sun_rise_icon, label: "Sunrise", time: root.day ? root.day.sunrise : "" }]
                delegate: sun_end
            }

            Canvas {
                id: sun_canvas
                Layout.fillWidth: true
                Layout.preferredHeight: 150

                Timer {
                    interval: 60000
                    running: root.is_today
                    repeat: true
                    onTriggered: sun_canvas.requestPaint()
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const w = width, h = height;
                    const cx = w / 2, cy = h - 12, r = Math.min(w / 2 - 12, h - 24);

                    ctx.strokeStyle = Theme.fg_muted;
                    ctx.lineWidth = 3;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, Math.PI, 0, false);
                    ctx.stroke();

                    ctx.strokeStyle = Theme.fg_dim;
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(0, cy);
                    ctx.lineTo(w, cy);
                    ctx.stroke();

                    const frac = root.sun_fraction();
                    if (frac !== null) {
                        const angle = Math.PI - frac * Math.PI;
                        ctx.fillStyle = Theme.yellow;
                        ctx.beginPath();
                        ctx.arc(cx + r * Math.cos(angle), cy - r * Math.sin(angle), 9, 0, 2 * Math.PI);
                        ctx.fill();
                    }
                }

                onWidthChanged: requestPaint()

                Connections {
                    target: root
                    function onDayChanged() { sun_canvas.requestPaint(); }
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 20
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Day length"; color: Theme.fg_muted; font.family: Style.font_family; font.pixelSize: Style.font_size - 3 }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.day_length(); color: Theme.fg_core; font.family: Style.font_family; font.pixelSize: Style.font_size + 2 }
                }
            }

            Repeater {
                model: [{ icon: WeatherState.sun_set_icon, label: "Sunset", time: root.day ? root.day.sunset : "" }]
                delegate: sun_end
            }
        }

        Component {
            id: sun_end

            ColumnLayout {
                required property var modelData
                Layout.alignment: Qt.AlignBottom
                spacing: 0

                Image {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    source: modelData.icon
                    sourceSize.width: 112
                    sourceSize.height: 112
                }
                Text { Layout.alignment: Qt.AlignHCenter; text: modelData.label; color: Theme.fg_muted; font.family: Style.font_family; font.pixelSize: Style.font_size - 3 }
                Text { Layout.alignment: Qt.AlignHCenter; text: modelData.time || "—"; color: Theme.fg_core; font.family: Style.font_family; font.pixelSize: Style.font_size + 4; font.bold: true }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 14

            Image {
                Layout.preferredWidth: 110
                Layout.preferredHeight: 110
                source: WeatherState.moon_icon_source(root.moon_phase)
                sourceSize.width: 220
                sourceSize.height: 220
            }

            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true

                Text {
                    text: WeatherState.moon_name(root.moon_phase)
                    color: Theme.fg_core
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size + 2
                    font.bold: true
                }

                Text {
                    text: "Moonrise " + (root.moon_times.rise || "—") + (root.moon_times.set ? "  ·  Moonset " + root.moon_times.set : "")
                    color: Theme.fg_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size - 2
                }

                Text {
                    text: "Full moon " + root.next_full
                    color: Theme.fg_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size - 2
                }
            }
        }
    }
}
