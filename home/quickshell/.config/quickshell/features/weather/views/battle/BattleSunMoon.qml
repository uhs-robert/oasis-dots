import QtQuick
import QtQuick.Layouts
import qs.ui.effects
import qs.theme
import qs.features.weather
import qs.styles.nes.widgets
import "NesSprites.js" as NesSprites

// The inn: the innkeeper's lines about the selected day's sun, a status window of day length and moon, and the day window strip with the DQ cursor.
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
    readonly property real sun_fraction: root.sun_up ? (root.now_minutes - root.rise_minutes) / (root.set_minutes - root.rise_minutes) : -1

    readonly property bool risen: root.is_today && root.now_minutes >= root.rise_minutes
    readonly property bool fallen: root.is_today && root.now_minutes >= root.set_minutes

    readonly property string rise_line: !root.has_sun ? "The sun is nowhere to be found." : "The sun " + (root.risen ? "rose" : "rises") + " at " + WeatherState.fmt_hm(root.day.sunrise) + "."
    readonly property string set_line: !root.has_sun ? "" : "Night " + (root.fallen ? "fell" : "falls") + " at " + WeatherState.fmt_hm(root.day.sunset) + "."

    function hm_minutes(hm) {
        const parts = (hm || "").split(":");
        return parts.length === 2 ? parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10) : -1;
    }

    function day_length() {
        if (!root.has_sun) return "—";
        const mins = root.set_minutes - root.rise_minutes;
        return Math.floor(mins / 60) + "H " + (mins % 60) + "M";
    }

    function day_label(i) {
        return i === 0 ? "NOW" : Qt.formatDate(new Date(WeatherState.days[i].date + "T00:00:00"), "ddd").toUpperCase();
    }

    Timer {
        interval: 60000
        running: root.is_today
        repeat: true
        onTriggered: root.clock_tick++
    }

    BattlePalette {
        id: palette
    }

    component StatRow: RowLayout {
        id: stat
        property string label: ""
        property string value: ""
        property color value_color: Style.pal.fg_strong

        Layout.fillWidth: true
        spacing: 8

        Text {
            Layout.preferredWidth: stat_metrics.advanceWidth("MOON ")
            text: stat.label
            color: Style.caret_color
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: stat.value || "—"
            color: stat.value_color
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
        }
    }

    FontMetrics {
        id: stat_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: WeatherState.days.slice(root.first_day, root.first_day + root.day_span)

                DqWindow {
                    id: day_cell
                    required property var modelData
                    required property int index
                    readonly property int day_index: root.first_day + day_cell.index
                    readonly property bool selected: day_cell.day_index === root.day_cursor

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: day_text.implicitHeight + 20
                    opacity: day_cell.selected ? 1 : 0.55

                    Text {
                        id: day_text
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 16)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: root.day_label(day_cell.day_index)
                        color: Style.pal.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-5)

                        Text {
                            visible: day_cell.selected && Style.caret_phase
                            anchors.right: parent.left
                            anchors.rightMargin: 3
                            anchors.verticalCenter: parent.verticalCenter
                            text: Style.row_cursor
                            color: Style.caret_color
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-6)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(day_cell.day_index)
                    }
                }
            }
        }

        DqWindow {
            Layout.fillWidth: true
            implicitHeight: lines.implicitHeight + 28

            ColumnLayout {
                id: lines
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.day ? root.rise_line : ""
                    color: Style.pal.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                    lineHeight: 1.3
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    wrapMode: Text.WordWrap
                    text: root.day ? root.set_line : ""
                    color: Style.pal.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                    lineHeight: 1.3
                }
            }
        }

        DqWindow {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 120
            title: root.day ? root.day.date.substr(5).replace("-", "/") : ""

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Item {
                    id: arc_box
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 60
                    Layout.maximumHeight: 150

                    readonly property int sun_size: NesSprites.SUN_PIXEL.length * 2
                    readonly property real rx: Math.max(10, arc_box.width / 2 - arc_box.sun_size)
                    readonly property real ry: Math.max(6, arc_box.height - arc_box.sun_size - 6)
                    readonly property real cx: arc_box.width / 2
                    readonly property real cy: arc_box.height - 4

                    onWidthChanged: arc_canvas.requestPaint()
                    onHeightChanged: arc_canvas.requestPaint()

                    Canvas {
                        id: arc_canvas
                        anchors.fill: parent
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            ctx.fillStyle = String(Style.text_muted);
                            for (let x = 0; x < width; x += 6) ctx.fillRect(x, arc_box.cy, 3, 2);
                            const steps = Math.max(8, Math.round(arc_box.rx / 5));
                            ctx.fillStyle = String(Style.pal.fg_strong);
                            ctx.globalAlpha = 0.5;
                            for (let i = 0; i <= steps; i++) {
                                const a = Math.PI * i / steps;
                                ctx.fillRect(Math.round(arc_box.cx - arc_box.rx * Math.cos(a)) - 1, Math.round(arc_box.cy - arc_box.ry * Math.sin(a)) - 1, 3, 3);
                            }
                        }
                    }

                    Connections {
                        target: Style
                        function onPalChanged() { arc_canvas.requestPaint(); }
                    }

                    PixelSprite {
                        visible: root.sun_fraction >= 0
                        pixel: 2
                        colors: palette.colors
                        rows: NesSprites.SUN_PIXEL
                        x: Math.round(arc_box.cx - arc_box.rx * Math.cos(Math.PI * root.sun_fraction) - width / 2)
                        y: Math.round(arc_box.cy - arc_box.ry * Math.sin(Math.PI * root.sun_fraction) - height / 2)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    PixelSprite {
                        Layout.alignment: Qt.AlignTop
                        pixel: 4
                        colors: palette.colors
                        rows: NesSprites.moon(root.moon_phase)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        StatRow { label: "DAY"; value: root.day_length() }
                        StatRow { label: "MOON"; value: root.day ? WeatherState.moon_name(root.moon_phase).toUpperCase() : "" }
                        StatRow { label: "RISE"; value: root.moon_times.rise }
                        StatRow { label: "SET"; value: root.moon_times.set }
                        StatRow { label: "FULL"; value: root.next_full }
                    }
                }
            }
        }
    }
}
