import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.styles.halflife.widgets
import qs.features.weather

// Sun & Moon as a Black Mesa Transit System departures board under the Daily day strip: each sky event is a "train"
// with its time and a status that, for today, says whether it has already left.
Item {
    id: root

    property int day_cursor: 0
    property int first_day: 0
    property int day_span: 5
    property var on_select: function (i) {}

    readonly property color hl: Style.text_primary
    readonly property color hl_t: Style.text_muted
    readonly property var day: WeatherState.days[Math.max(0, Math.min(WeatherState.days.length - 1, root.day_cursor))]
    readonly property bool is_today: root.day_cursor === 0

    readonly property var moon_times: root.day ? WeatherState.moon_times_for_date(root.day.date) : ({ rise: null, set: null })
    readonly property real moon_phase: root.day ? WeatherState.moon_phase_for_date(root.day.date) : 0
    readonly property real moon_lit: (1 - Math.cos(2 * Math.PI * root.moon_phase)) / 2
    readonly property string next_full: root.day ? WeatherState.next_full_moon_label(root.day.date) : ""
    readonly property int days_to_full: Math.round((((0.5 - root.moon_phase) % 1 + 1) % 1) * WeatherState.lunar_cycle_days)

    readonly property int rise_min: root.hm_minutes(root.day ? root.day.sunrise : "")
    readonly property int set_min: root.hm_minutes(root.day ? root.day.sunset : "")
    readonly property bool has_sun: root.rise_min >= 0 && root.set_min > root.rise_min
    property int now_min: root.location_minutes()

    // The sun's position along today's daylight, or -1 outside daylight and on other days.
    readonly property real sun_fraction: root.is_today && root.has_sun && root.now_min >= root.rise_min && root.now_min <= root.set_min ? (root.now_min - root.rise_min) / (root.set_min - root.rise_min) : -1

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

    // Boarding in the last half hour before an event, departed once it has passed; other days only have a schedule.
    function status_of(event_min) {
        if (!root.is_today) return "SCHEDULED";
        const delta = event_min - root.now_min;
        if (delta < 0) return "DEPARTED";
        return delta <= 30 ? "BOARDING" : "ON TIME";
    }

    function sun_status() {
        if (!root.is_today) return "SCHEDULED";
        if (root.sun_fraction >= 0) return "SOL ALOFT " + Math.round(root.sun_fraction * 100) + "%";
        return root.now_min < root.rise_min ? "SOL BELOW HORIZON" : "SOL DEPARTED";
    }

    Timer {
        interval: 60000
        running: root.is_today
        repeat: true
        onTriggered: root.now_min = root.location_minutes()
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
                    readonly property bool open: day_cell.day_index === root.day_cursor

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: 20
                    color: day_cell.open ? root.hl : "transparent"
                    border.width: day_cell.open ? 0 : 1
                    border.color: Style.hairline_dim

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 4
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: (day_cell.width >= 60 ? day_cell.modelData.weekday : Qt.formatDate(new Date(day_cell.modelData.date + "T00:00:00"), "ddd")).toUpperCase()
                        color: day_cell.open ? Theme.bg_crust : root.hl_t
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                        font.bold: true
                        font.letterSpacing: day_cell.open ? 1.3 : 0.5
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(day_cell.day_index)
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.bg_crust
            border.width: 1
            border.color: Style.hairline

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: head_text.implicitHeight + 6
                    color: root.hl

                    Text {
                        id: head_text
                        x: 8
                        width: parent.width - 16
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: "BLACK MESA TRANSIT SYSTEM"
                        color: Theme.bg_crust
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                        font.bold: true
                        font.letterSpacing: root.width >= 300 ? 2.8 : 1
                    }

                    Text {
                        visible: !!root.day && root.width >= 300
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.day ? root.day.date.substr(5).replace("-", " / ") : ""
                        color: Theme.bg_crust
                        font.family: Style.number_font
                        font.pixelSize: Style.fs(-5)
                        font.bold: true
                        font.letterSpacing: 1
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 8
                    Layout.topMargin: 5
                    Layout.bottomMargin: 3
                    spacing: 8

                    ColumnHead {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: "SKY EVENT"
                    }

                    ColumnHead {
                        Layout.preferredWidth: time_w
                        text: "TIME"
                    }

                    ColumnHead {
                        Layout.preferredWidth: status_w
                        text: "STATUS"
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Style.hairline_dim
                }

                Board {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Style.hairline_dim
                }

                // Today's sun along its daylight, cells lit up to where it is now.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 8
                    Layout.topMargin: 6
                    spacing: 3

                    SkewBar {
                        Layout.fillWidth: true
                        Layout.rightMargin: 4
                        cells: 16
                        value: root.sun_fraction >= 0 ? root.sun_fraction : 0
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        ColumnHead {
                            text: "SOL " + (root.has_sun ? WeatherState.fmt_hm(root.day.sunrise) : "--")
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        ColumnHead {
                            color: root.sun_fraction >= 0 ? root.hl : root.hl_t
                            text: root.sun_status()
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        ColumnHead {
                            text: (root.has_sun ? WeatherState.fmt_hm(root.day.sunset) : "--") + " SET"
                        }
                    }
                }
            }
        }
    }

    readonly property real time_w: 74
    readonly property real status_w: root.width >= 340 ? 128 : 92

    component ColumnHead: Text {
        color: root.hl_t
        elide: Text.ElideRight
        font.family: Style.font_family
        font.pixelSize: Style.fs(-6)
        font.bold: true
        font.letterSpacing: 2
    }

    component Board: ColumnLayout {
        spacing: 0

        BoardRow {
            banded: true
            label: "SUNRISE"
            time: root.day ? WeatherState.fmt_hm(root.day.sunrise) : ""
            status: root.has_sun ? root.status_of(root.rise_min) : ""
        }

        BoardRow {
            label: "SUNSET"
            time: root.day ? WeatherState.fmt_hm(root.day.sunset) : ""
            status: root.has_sun ? root.status_of(root.set_min) : ""
        }

        BoardRow {
            banded: true
            label: "DAY LENGTH"
            time: root.day_length()
            status: ""
        }

        BoardRow {
            label: "MOONRISE"
            time: root.moon_times.rise || ""
            status: root.moon_times.always_up ? "ALL DAY" : ""
        }

        BoardRow {
            banded: true
            label: "MOONSET"
            time: root.moon_times.set || ""
            status: root.moon_times.always_down ? "NO SERVICE" : ""
        }

        BoardRow {
            label: "MOON PHASE"
            time: Math.round(root.moon_lit * 100) + "%"
            status: WeatherState.moon_name(root.moon_phase).toUpperCase()
            icon: WeatherState.moon_icon_source(root.moon_phase)
        }

        BoardRow {
            banded: true
            label: "NEXT FULL MOON"
            time: root.next_full.toUpperCase()
            status: root.days_to_full === 0 ? "TONIGHT" : "IN " + root.days_to_full + " D"
        }
    }

    component BoardRow: Item {
        id: board_row
        property string label: ""
        property string time: ""
        property string status: ""
        property url icon: ""
        property bool banded: false
        Layout.fillWidth: true
        Layout.fillHeight: true

        // Alternate rows carry a faint band, like the lit rows of a departures board.
        Rectangle {
            anchors.fill: parent
            visible: board_row.banded
            color: Style.selection_bg
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            Item {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20

                Image {
                    anchors.fill: parent
                    visible: board_row.icon.toString() !== ""
                    source: board_row.icon
                    sourceSize.width: 40
                    sourceSize.height: 40
                    smooth: true
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                elide: Text.ElideRight
                text: board_row.label
                color: root.hl_t
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
                font.bold: true
                font.letterSpacing: 1.5
            }

            Text {
                Layout.preferredWidth: root.time_w
                elide: Text.ElideRight
                text: board_row.time !== "" ? board_row.time : "--"
                color: root.hl
                font.family: Style.number_font
                font.pixelSize: Style.fs(2)
                font.bold: true
            }

            Text {
                Layout.preferredWidth: root.status_w
                elide: Text.ElideRight
                text: board_row.status
                color: board_row.status === "BOARDING" ? Theme.theme_label : root.hl_t
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.bold: true
                font.letterSpacing: 1
            }
        }
    }
}
