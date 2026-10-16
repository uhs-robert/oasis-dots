import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../services"

// WeatherStar 4000 "Almanac": sunrise and sunset for the selected day and the next, the next four moon phases,
// and the selected day's moonrise and moonset. The day strip on top picks the day.
Item {
    id: root

    property int day_cursor: 0
    property int first_day: 0
    property int day_span: 5
    property var on_select: function (i) {}

    readonly property var days: WeatherState.days
    readonly property var day: root.days[Math.max(0, Math.min(root.days.length - 1, root.day_cursor))]
    // The Almanac's second column; empty on the last forecast day.
    readonly property var next_day: root.day_cursor + 1 < root.days.length ? root.days[root.day_cursor + 1] : null
    readonly property var moon_times: root.day ? WeatherState.moon_times_for_date(root.day.date) : ({ rise: null, set: null })

    // New, First, Full and Last as lunar-cycle fractions.
    readonly property var phase_targets: [
        { fraction: 0, name: "New", slug: "moon-new" },
        { fraction: 0.25, name: "First", slug: "moon-first-quarter" },
        { fraction: 0.5, name: "Full", slug: "moon-full" },
        { fraction: 0.75, name: "Last", slug: "moon-last-quarter" }
    ]

    // Closed form like WeatherState.next_full_moon_label: the phase advances at a constant rate.
    readonly property var upcoming_phases: {
        if (!root.day) return [];
        const noon = WeatherState.local_midnight_ms(root.day.date) + 12 * 3600000;
        const phase = WeatherState.moon_phase_for_date(root.day.date);
        return root.phase_targets.map(p => {
            const days_ahead = (((p.fraction - phase) % 1 + 1) % 1) * WeatherState.lunar_cycle_days;
            const shifted = new Date(noon + days_ahead * 86400000 + WeatherState.utc_offset * 1000);
            return { name: p.name, slug: p.slug, ahead: days_ahead, date: WeatherState.month_names[shifted.getUTCMonth()] + " " + shifted.getUTCDate() };
        }).sort((a, b) => a.ahead - b.ahead);
    }

    function hm_minutes(hm) {
        if (!hm) return null;
        const parts = hm.split(":");
        if (parts.length !== 2) return null;
        return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
    }

    function day_length(d) {
        const rise = d ? root.hm_minutes(d.sunrise) : null;
        const set = d ? root.hm_minutes(d.sunset) : null;
        if (rise === null || set === null || set <= rise) return "--";
        const mins = set - rise;
        return Math.floor(mins / 60) + "h " + (mins % 60) + "m";
    }

    function sun_cell(d, key) {
        return d ? (WeatherState.fmt_hm(d[key]) || "--") : "";
    }

    readonly property var table_rows: [
        { label: "Sunrise", cells: [root.sun_cell(root.day, "sunrise"), root.sun_cell(root.next_day, "sunrise")] },
        { label: "Sunset", cells: [root.sun_cell(root.day, "sunset"), root.sun_cell(root.next_day, "sunset")] },
        { label: "Length", cells: [root.day ? root.day_length(root.day) : "", root.next_day ? root.day_length(root.next_day) : ""] }
    ]

    component Label: Text {
        color: Theme.fg_strong
        font.family: Style.font_family
        font.pixelSize: Style.fs(-3)
        style: Text.Outline
        styleColor: Theme.bg_shadow
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: root.days.slice(root.first_day, root.first_day + root.day_span)

                Item {
                    id: day_cell
                    required property var modelData
                    required property int index
                    readonly property int day_index: root.first_day + day_cell.index

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: day_text.implicitHeight + 8

                    WsPanel {
                        anchors.fill: parent
                        lit: day_cell.day_index === root.day_cursor
                    }

                    Label {
                        id: day_text
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 4)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: day_cell.modelData.weekday
                        color: day_cell.day_index === root.day_cursor ? Theme.theme_secondary : Theme.fg_strong
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(day_cell.day_index)
                    }
                }
            }
        }

        Text {
            text: "Almanac"
            color: Theme.theme_secondary
            font.family: Style.font_family
            font.pixelSize: Style.fs(-1)
            style: Text.Outline
            styleColor: Theme.bg_shadow
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: sun_table.implicitHeight + 16

            WsPanel {
                anchors.fill: parent
            }

            GridLayout {
                id: sun_table
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                columns: 3
                columnSpacing: 8
                rowSpacing: 2

                Item { Layout.fillWidth: true }

                Repeater {
                    model: [root.day, root.next_day]

                    Label {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        horizontalAlignment: Text.AlignRight
                        text: modelData ? modelData.weekday : ""
                        color: Theme.theme_secondary
                    }
                }

                Repeater {
                    model: root.table_rows

                    Repeater {
                        id: table_row
                        required property var modelData
                        model: 3

                        Label {
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredWidth: index === 0 ? 1 : 0
                            horizontalAlignment: index === 0 ? Text.AlignLeft : Text.AlignRight
                            text: index === 0 ? table_row.modelData.label : table_row.modelData.cells[index - 1]
                            color: index === 0 ? Theme.theme_primary_light : Theme.fg_strong
                            font.pixelSize: index === 0 ? Style.fs(-3) : Style.fs(-2)
                        }
                    }
                }
            }
        }

        Text {
            text: "Moon Phases"
            color: Theme.theme_secondary
            font.family: Style.font_family
            font.pixelSize: Style.fs(-1)
            style: Text.Outline
            styleColor: Theme.bg_shadow
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            WsPanel {
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 4

                    Repeater {
                        model: root.upcoming_phases

                        ColumnLayout {
                            id: phase_col
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            Layout.fillHeight: true
                            spacing: 0

                            Item { Layout.fillHeight: true }

                            Image {
                                readonly property real size: Math.max(24, Math.min(56, phase_col.width - 8))
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: size
                                Layout.preferredHeight: size
                                readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                                sourceSize.width: Math.ceil(112 * dpr)
                                sourceSize.height: Math.ceil(112 * dpr)
                                source: WeatherState.asset_url(phase_col.modelData.slug)
                                smooth: true
                            }

                            Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: phase_col.modelData.name
                                color: Theme.theme_primary_light
                            }

                            Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: phase_col.modelData.date
                                font.pixelSize: Style.fs(-2)
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "Moonrise " + (root.moon_times.rise || "--")
                    }

                    Label {
                        visible: !!root.moon_times.set
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        text: "Moonset " + (root.moon_times.set || "")
                    }
                }
            }
        }
    }
}
