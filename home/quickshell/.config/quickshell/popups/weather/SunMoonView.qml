// home/quickshell/.config/quickshell/popups/weather/SunMoonView.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"

// Daily's Sun & Moon sub-view: the Daily day window as a strip, the selected day's sun arc
// (today shows the current-position dot), moon phase, moonrise/moonset and next full moon.
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

    component SunEnd: RowLayout {
        id: sun_end
        property string icon: ""
        property string label: ""
        property string time: ""
        spacing: 6

        Image {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            source: sun_end.icon
            sourceSize.width: 64
            sourceSize.height: 64
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: sun_end.label; color: Style.text_muted; font.family: Style.font_family; font.pixelSize: Style.fs(-3) }
            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: sun_end.time || "—"; color: Theme.fg_core; font.family: Style.font_family; font.pixelSize: Style.fs(2); font.bold: true }
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

                Rectangle {
                    id: day_cell
                    required property var modelData
                    required property int index
                    readonly property int day_index: root.first_day + day_cell.index

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: day_text.implicitHeight + 6
                    radius: Style.radius(4)
                    color: day_cell.day_index !== root.day_cursor ? "transparent" : Style.selection_brackets.a > 0 ? Style.selection_bg : Theme.bg_surface

                    LockBrackets {
                        shown: day_cell.day_index === root.day_cursor
                    }

                    Text {
                        id: day_text
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 4)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: day_cell.modelData.weekday
                        color: day_cell.day_index === root.day_cursor ? Theme.theme_secondary : Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(day_cell.day_index)
                    }
                }
            }
        }

        Canvas {
            id: sun_canvas
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 90

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
                const cx = w / 2, cy = h - 12, r = Math.max(10, Math.min(w / 2 - 12, h - 24));

                ctx.strokeStyle = Style.text_muted;
                ctx.lineWidth = 3;
                ctx.beginPath();
                ctx.arc(cx, cy, r, Math.PI, 0, false);
                ctx.stroke();

                ctx.strokeStyle = Style.text_dim;
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
            onHeightChanged: requestPaint()

            Connections {
                target: root
                function onDayChanged() { sun_canvas.requestPaint(); }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 20
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.day ? root.day.date.substr(5) : ""; color: Style.text_dim; font.family: Style.font_family; font.pixelSize: Style.fs(-3) }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Day length"; color: Style.text_muted; font.family: Style.font_family; font.pixelSize: Style.fs(-3) }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.day_length(); color: Theme.fg_core; font.family: Style.font_family; font.pixelSize: Style.fs(2) }
            }
        }

        // Sunrise and sunset share a row when both fit, else stack.
        GridLayout {
            id: sun_ends
            Layout.fillWidth: true
            columns: sun_ends.width >= rise_end.implicitWidth + set_end.implicitWidth + sun_ends.columnSpacing ? 2 : 1
            columnSpacing: 12
            rowSpacing: 4

            SunEnd {
                id: rise_end
                Layout.fillWidth: true
                icon: WeatherState.sun_rise_icon
                label: "Sunrise"
                time: root.day ? root.day.sunrise : ""
            }

            SunEnd {
                id: set_end
                Layout.fillWidth: true
                icon: WeatherState.sun_set_icon
                label: "Sunset"
                time: root.day ? root.day.sunset : ""
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Image {
                readonly property real size: Math.min(88, Math.max(48, root.width / 4))
                Layout.preferredWidth: size
                Layout.preferredHeight: size
                source: WeatherState.moon_icon_source(root.moon_phase)
                sourceSize.width: 176
                sourceSize.height: 176
            }

            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: WeatherState.moon_name(root.moon_phase)
                    color: Theme.fg_core
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(2)
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: "Moonrise " + (root.moon_times.rise || "—")
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-2)
                }

                Text {
                    visible: !!root.moon_times.set
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: "Moonset " + (root.moon_times.set || "")
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-2)
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: "Full moon " + root.next_full
                    color: Style.text_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-2)
                }
            }
        }
    }
}
