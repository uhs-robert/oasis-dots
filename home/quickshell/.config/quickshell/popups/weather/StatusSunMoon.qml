pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.theme
import qs.services

// Sun & Moon as two FF7 materia status pages: each body an orb with its stat rows, then AP-style gauges for today's
// sun and the moon's light, under a strip of menu tabs for the Daily day window.
Item {
    id: root

    property int day_cursor: 0
    property int first_day: 0
    property int day_span: 5
    property var on_select: function (i) {}

    readonly property var day: WeatherState.days[Math.max(0, Math.min(WeatherState.days.length - 1, root.day_cursor))]
    readonly property bool is_today: root.day_cursor === 0
    readonly property bool wide: root.width >= 340
    readonly property real page_w: root.wide ? (root.width - 8) / 2 : root.width

    readonly property var moon_times: root.day ? WeatherState.moon_times_for_date(root.day.date) : ({ rise: null, set: null })
    readonly property real moon_phase: root.day ? WeatherState.moon_phase_for_date(root.day.date) : 0
    readonly property real moon_lit: (1 - Math.cos(2 * Math.PI * root.moon_phase)) / 2
    readonly property string next_full: root.day ? WeatherState.next_full_moon_label(root.day.date) : ""

    readonly property int rise_min: root.hm_minutes(root.day ? root.day.sunrise : "")
    readonly property int set_min: root.hm_minutes(root.day ? root.day.sunset : "")
    readonly property bool has_sun: root.rise_min >= 0 && root.set_min > root.rise_min
    property int now_min: root.location_minutes()

    // Today's progress from sunrise to sunset, held at 0 before dawn and 1 after dusk; -1 for other days.
    readonly property real sun_progress: root.is_today && root.has_sun ? Math.max(0, Math.min(1, (root.now_min - root.rise_min) / (root.set_min - root.rise_min))) : -1

    function hm_minutes(hm) {
        const parts = (hm || "").split(":");
        return parts.length === 2 ? parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10) : -1;
    }

    function location_minutes() {
        const loc = WeatherState.location_now();
        return loc.getUTCHours() * 60 + loc.getUTCMinutes();
    }

    function duration_text(mins) {
        return Math.floor(mins / 60) + "h " + (mins % 60) + "m";
    }

    function day_length() {
        return root.has_sun ? root.duration_text(root.set_min - root.rise_min) : "--";
    }

    function sun_caption() {
        if (!root.has_sun) return "";
        if (!root.is_today) return "pick today for the live sun";
        if (root.now_min < root.rise_min) return "sunrise in " + root.duration_text(root.rise_min - root.now_min);
        if (root.now_min > root.set_min) return "the sun has set";
        return root.duration_text(root.set_min - root.now_min) + " to sunset";
    }

    Timer {
        interval: 60000
        running: root.is_today
        repeat: true
        onTriggered: root.now_min = root.location_minutes()
    }

    component Label: Text {
        color: Theme.theme_primary_light
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
        font.weight: Font.ExtraBold
        font.letterSpacing: 1
    }

    component Value: Text {
        horizontalAlignment: Text.AlignRight
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 9
        color: Theme.fg_strong
        font.family: Style.font_family
        font.pixelSize: Style.fs(-1)
        font.weight: Font.ExtraBold
    }

    component StatRow: RowLayout {
        id: stat
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: 6

        Label {
            text: stat.label
        }

        Value {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: stat.value || "--"
        }
    }

    // One body's page: orb and name up top, its rows below.
    component BodyPage: Item {
        id: page
        property string title: ""
        property color orb_color: "transparent"
        property url icon: ""
        default property alias rows: rows_col.data

        implicitHeight: page_body.implicitHeight + 20

        StatusWindow {
            anchors.fill: parent
        }

        ColumnLayout {
            id: page_body
            anchors.fill: parent
            anchors.margins: 10
            anchors.topMargin: 9
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 9

                MateriaOrb {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    color: page.orb_color
                }

                Text {
                    Layout.fillWidth: true
                    text: page.title
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(2)
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.5
                }

                Image {
                    visible: page.icon != ""
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    source: page.icon
                    sourceSize.width: 60
                    sourceSize.height: 60
                    smooth: true
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Style.frame_inset_color
            }

            ColumnLayout {
                id: rows_col
                Layout.fillWidth: true
                spacing: 5
            }
        }
    }

    component GaugeRow: RowLayout {
        id: gauge
        property string label: ""
        property real value: 0
        property string value_text: ""
        property color fill: Theme.theme_secondary
        Layout.fillWidth: true
        spacing: 8

        Label {
            Layout.preferredWidth: 26
            text: gauge.label
        }

        AtbBar {
            Layout.fillWidth: true
            Layout.preferredHeight: 11
            value: gauge.value
            fill_color: gauge.fill
            shade_color: Qt.tint(gauge.fill, Qt.alpha(Theme.fg_strong, 0.55))
            ticks: true
        }

        Value {
            Layout.preferredWidth: 46
            text: gauge.value_text
            font.pixelSize: Style.fs(-2)
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
                    id: tab
                    required property var modelData
                    required property int index
                    readonly property int day_index: root.first_day + tab.index
                    readonly property bool open: tab.day_index === root.day_cursor

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: day_text.implicitHeight + 10

                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: tab.open ? Qt.alpha(Theme.fg_strong, 0.1) : "transparent"
                        border.width: 1
                        border.color: tab.open ? Style.frame_border_color : Style.chip_border
                    }

                    HandCursor {
                        visible: tab.open && tab.width >= 52
                        x: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 9
                    }

                    Text {
                        id: day_text
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: tab.open && tab.width >= 52 ? 6 : 0
                        width: Math.min(implicitWidth, parent.width - (tab.open && tab.width >= 52 ? 26 : 6))
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: tab.width >= 60 ? tab.modelData.weekday : Qt.formatDate(new Date(tab.modelData.date + "T00:00:00"), "ddd")
                        color: tab.open ? Theme.fg_strong : Theme.theme_primary_light
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                        font.weight: tab.open ? Font.ExtraBold : Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(tab.day_index)
                    }
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: root.wide ? 2 : 1
            columnSpacing: 8
            rowSpacing: 8

            BodyPage {
                Layout.preferredWidth: root.page_w
                Layout.maximumWidth: root.page_w
                Layout.alignment: Qt.AlignTop
                title: "SUN"
                orb_color: Style.materia_palette.clear
                icon: WeatherState.icon_source(0, true)

                StatRow { label: "SUNRISE"; value: root.day ? WeatherState.fmt_hm(root.day.sunrise) : "" }
                StatRow { label: "SUNSET"; value: root.day ? WeatherState.fmt_hm(root.day.sunset) : "" }
                StatRow { label: "DAY LENGTH"; value: root.day_length() }
            }

            BodyPage {
                Layout.preferredWidth: root.page_w
                Layout.maximumWidth: root.page_w
                Layout.alignment: Qt.AlignTop
                title: "MOON"
                orb_color: Style.materia_palette.snow
                icon: WeatherState.moon_icon_source(root.moon_phase)

                StatRow { label: "PHASE"; value: WeatherState.moon_name(root.moon_phase) }
                StatRow { label: "MOONRISE"; value: root.moon_times.rise || "" }
                StatRow { label: "MOONSET"; value: root.moon_times.set || "" }
                StatRow { label: "NEXT FULL"; value: root.next_full }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: gauge_body.implicitHeight + 20

            StatusWindow {
                anchors.fill: parent
            }

            ColumnLayout {
                id: gauge_body
                anchors.fill: parent
                anchors.margins: 9
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 5

                GaugeRow {
                    label: "AP"
                    value: Math.max(0, root.sun_progress)
                    value_text: root.sun_progress >= 0 ? Math.round(root.sun_progress * 100) + "%" : "--"
                    fill: Theme.theme_secondary
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 34
                    elide: Text.ElideRight
                    text: root.sun_caption()
                    color: Theme.theme_primary_light
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                    font.weight: Font.DemiBold
                }

                GaugeRow {
                    label: "LIT"
                    value: root.moon_lit
                    value_text: Math.round(root.moon_lit * 100) + "%"
                    fill: Theme.theme_primary_light
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 34
                    elide: Text.ElideRight
                    text: root.day ? "moon light on " + root.day.date.substr(5) : ""
                    color: Theme.theme_primary_light
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                    font.weight: Font.DemiBold
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
