import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.styles.ps1.widgets
import qs.theme
import qs.services

// Daily's Sun & Moon sub-view as the PS1 BIOS clock screen: the days as memory card slot tabs over a panel setting
// sunrise and sunset like the clock fields, with day length and today's live sun position as block gauges,
// and the moon phase as a lit save with its rise, set and next full moon.
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

    readonly property var sunrise_min: root.hm_minutes(root.day ? root.day.sunrise : "")
    readonly property var sunset_min: root.hm_minutes(root.day ? root.day.sunset : "")
    readonly property bool has_sun: root.sunrise_min !== null && root.sunset_min !== null && root.sunset_min > root.sunrise_min
    readonly property int daylight_min: root.has_sun ? root.sunset_min - root.sunrise_min : 0
    // The location clock only changes on the minute; reading clock.date re-evaluates the fraction then.
    readonly property var sun_frac: { clock.date; return root.sun_fraction(); }

    function hm_minutes(hm) {
        if (!hm) return null;
        const parts = hm.split(":");
        if (parts.length !== 2) return null;
        return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
    }

    function sun_fraction() {
        if (!root.is_today || !root.has_sun) return null;
        const loc = WeatherState.location_now();
        const now = loc.getUTCHours() * 60 + loc.getUTCMinutes();
        if (now < root.sunrise_min || now > root.sunset_min) return null;
        return (now - root.sunrise_min) / root.daylight_min;
    }

    function day_length() {
        return root.has_sun ? Math.floor(root.daylight_min / 60) + "H " + (root.daylight_min % 60) + "M" : "--";
    }

    function sun_text() {
        if (root.sun_frac !== null) return Math.round(root.sun_frac * 100) + "%";
        return root.is_today && root.has_sun ? "NIGHT" : "--";
    }

    // "7:09am" or "07:09" as [hour, minute, suffix] fields.
    function clock_fields(hm) {
        const m = /^(\d{1,2}):(\d{2})\s*(.*)$/.exec(WeatherState.fmt_hm(hm) || "");
        return m ? [m[1], m[2], m[3].toUpperCase()] : ["--", "--", ""];
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    component Field: Rectangle {
        id: field
        property string text: ""
        property bool arrows: true

        implicitWidth: Math.max(34, field_text.implicitWidth + 12)
        implicitHeight: 36
        radius: 3
        color: Qt.alpha(Theme.bg_crust, 0.75)
        border.width: 1
        border.color: Qt.alpha(Theme.blue, 0.7)

        Text {
            visible: field.arrows
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.top
            text: "▲"
            color: Style.text_dim
            font.pixelSize: Style.fs(-6)
        }

        Text {
            visible: field.arrows
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            text: "▼"
            color: Style.text_dim
            font.pixelSize: Style.fs(-6)
        }

        Text {
            id: field_text
            anchors.centerIn: parent
            text: field.text
            color: Style.text_strong
            font.family: Style.font_family
            font.pixelSize: Style.fs(3)
            style: Text.Raised
            styleColor: Style.text_shadow
        }
    }

    component SetClock: RowLayout {
        id: set_clock
        property string label: ""
        property string hm: ""
        readonly property var fields: root.clock_fields(set_clock.hm)

        spacing: 6

        ColumnLayout {
            spacing: 16

            Text {
                text: set_clock.label
                color: Theme.theme_primary_light
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 1
            }

            Row {
                spacing: 3

                Field { text: set_clock.fields[0] }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ":"
                    color: Style.text_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(3)
                }

                Field { text: set_clock.fields[1] }

                Field {
                    visible: set_clock.fields[2] !== ""
                    arrows: false
                    text: set_clock.fields[2]
                }
            }
        }
    }

    component GaugeRow: RowLayout {
        id: gauge_row
        property string label: ""
        property real value: 0
        property color fill_color: Theme.theme_primary_light
        property bool mark_last: false
        property string text: ""

        Layout.fillWidth: true
        spacing: 8

        Text {
            Layout.preferredWidth: 64
            text: gauge_row.label
            color: Theme.theme_primary_light
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
        }

        BlockGauge {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            value: gauge_row.value
            fill_color: gauge_row.fill_color
            mark_last: gauge_row.mark_last
        }

        Text {
            Layout.preferredWidth: 64
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: gauge_row.text
            color: Style.text_fg
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
        }
    }

    component PanelTitle: RowLayout {
        id: panel_title
        property string text: ""
        property string aside: ""

        Layout.fillWidth: true
        spacing: 6

        Text {
            text: panel_title.text
            color: Theme.theme_primary_light
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
            font.letterSpacing: 1
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Qt.alpha(Theme.theme_primary_light, 0.3)
        }

        Text {
            text: panel_title.aside
            color: Style.text_muted
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 3

            Repeater {
                model: WeatherState.days.slice(root.first_day, root.first_day + root.day_span)

                Rectangle {
                    id: slot_tab
                    required property var modelData
                    required property int index
                    readonly property int day_index: root.first_day + slot_tab.index
                    readonly property bool selected: slot_tab.day_index === root.day_cursor

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: tab_text.implicitHeight + 10
                    radius: 4
                    color: slot_tab.selected ? Style.selection_bg : Qt.alpha(Theme.bg_shadow, 0.45)
                    border.width: slot_tab.selected ? 2 : 1
                    border.color: slot_tab.selected ? Theme.theme_primary_light : Qt.alpha(Style.frame_border_color, 0.6)

                    Column {
                        id: tab_text
                        anchors.centerIn: parent
                        width: parent.width - 4

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: slot_tab.modelData.weekday.toUpperCase()
                            color: slot_tab.selected ? Style.text_strong : Style.text_fg
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                            style: slot_tab.selected ? Text.Raised : Text.Normal
                            styleColor: Style.text_shadow
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: slot_tab.modelData.date.substr(5).replace("-", "/")
                            color: slot_tab.selected ? Theme.theme_primary_light : Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-6)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(slot_tab.day_index)
                    }
                }
            }
        }

        BiosPanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: sun_col.implicitHeight + 20

            ColumnLayout {
                id: sun_col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 10
                spacing: 10

                PanelTitle {
                    text: "SUN"
                    aside: root.day ? Qt.formatDate(new Date(root.day.date + "T00:00:00"), "MMM d").toUpperCase() : ""
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 12

                    SetClock {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        label: "SUNRISE"
                        hm: root.day ? root.day.sunrise : ""
                    }

                    SetClock {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        label: "SUNSET"
                        hm: root.day ? root.day.sunset : ""
                    }
                }

                GaugeRow {
                    Layout.topMargin: 14
                    label: "DAYLIGHT"
                    value: root.daylight_min / 1440
                    fill_color: Style.pal.yellow
                    text: root.day_length()
                }

                GaugeRow {
                    label: "SUN"
                    value: root.sun_frac !== null ? root.sun_frac : 0
                    fill_color: Style.pal.bright_yellow
                    mark_last: root.sun_frac !== null
                    text: root.sun_text()
                }
            }
        }

        BiosPanel {
            Layout.fillWidth: true
            Layout.preferredHeight: moon_col.implicitHeight + 20

            ColumnLayout {
                id: moon_col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 6

                PanelTitle {
                    text: "MOON"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    SaveIcon {
                        Layout.alignment: Qt.AlignTop
                        size: 56
                        icon_url: WeatherState.moon_icon_source(root.moon_phase)
                        lit: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: WeatherState.moon_name(root.moon_phase).toUpperCase()
                            color: Style.text_strong
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-1)
                            style: Text.Raised
                            styleColor: Style.text_shadow
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: "RISE " + (root.moon_times.rise || "--") + "  SET " + (root.moon_times.set || "--")
                            color: Style.text_fg
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: "FULL MOON " + root.next_full.toUpperCase()
                            color: Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                        }
                    }
                }
            }
        }
    }
}
