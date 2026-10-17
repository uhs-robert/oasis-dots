import QtQuick
import QtQuick.Layouts
import qs.components
import qs.ui.effects
import qs.theme
import qs.services
import qs.ui.frames
import "PixelArt.js" as PixelArt

// The Pokégear clock and a Pokédex entry for the day's sun: MORN / DAY / NITE over a 24-hour strip, the sun's hours in a text box,
// and the moon phase drawn large on Mt. Moon with a one-line entry for its state. The day strip is the Pokégear's tabs.
Item {
    id: root

    property int day_cursor: 0
    property int first_day: 0
    property int day_span: 5
    property var on_select: function (i) {}

    readonly property var shades: Style.pixel_shades
    readonly property var day: WeatherState.days[Math.max(0, Math.min(WeatherState.days.length - 1, root.day_cursor))]
    readonly property bool is_today: root.day_cursor === 0

    readonly property var moon_times: root.day ? WeatherState.moon_times_for_date(root.day.date) : ({ rise: null, set: null })
    readonly property real moon_phase: root.day ? WeatherState.moon_phase_for_date(root.day.date) : 0
    readonly property string next_full: root.day ? WeatherState.next_full_moon_label(root.day.date) : ""
    readonly property string moon_flavour: {
        const key = WeatherState.moon_phase_key(root.moon_phase);
        if (key === "new") return "No moon tonight.";
        if (key === "full") return "The moon is full tonight.";
        return key.indexOf("waxing") === 0 ? "The moon is waxing." : "The moon is waning.";
    }

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
    readonly property bool risen: root.is_today && root.now_minutes >= root.rise_minutes
    readonly property bool fallen: root.is_today && root.now_minutes >= root.set_minutes

    // Gold and Silver's clock: morning from 4:00, day from 10:00, night from 18:00.
    readonly property var periods: [{ name: "MORN", start: 4 }, { name: "DAY", start: 10 }, { name: "NITE", start: 18 }]
    readonly property int period_index: {
        const hour = Math.floor(root.now_minutes / 60);
        return hour >= 18 || hour < 4 ? 2 : hour >= 10 ? 1 : 0;
    }

    readonly property string entry: !root.day ? "" : !root.has_sun ? "The sun is nowhere to be found."
        : "The sun " + (root.risen ? "rose" : "rises") + " at " + WeatherState.fmt_hm(root.day.sunrise).toUpperCase() + " and "
        + (root.fallen ? "set" : "sets") + " at " + WeatherState.fmt_hm(root.day.sunset).toUpperCase() + ". The day lasts " + root.day_length() + "."

    function hm_minutes(hm) {
        const parts = (hm || "").split(":");
        return parts.length === 2 ? parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10) : -1;
    }

    function day_length() {
        if (!root.has_sun) return "—";
        const mins = root.set_minutes - root.rise_minutes;
        return Math.floor(mins / 60) + "H " + (mins % 60) + "M";
    }

    function clock_text() {
        const mins = root.now_minutes;
        return WeatherState.fmt_hm(Math.floor(mins / 60) + ":" + String(mins % 60).padStart(2, "0")).toUpperCase();
    }

    function day_label(i) {
        return i === 0 ? "TODAY" : WeatherState.days[i].weekday.toUpperCase();
    }

    Timer {
        interval: 60000
        running: root.is_today
        repeat: true
        onTriggered: root.clock_tick++
    }

    // A box with its title chip set into the top border, as on the Pokégear's menus.
    component TitledBox: Item {
        id: titled
        property string title: ""
        default property alias content: body.data

        PixelBox {
            anchors.fill: parent
            anchors.topMargin: 4
            fill: root.shades[0]
            rings: [root.shades[2], root.shades[0]]
        }

        Rectangle {
            x: 10
            width: chip.implicitWidth + 8
            height: chip.implicitHeight + 2
            color: root.shades[2]

            Text {
                id: chip
                anchors.centerIn: parent
                text: titled.title
                color: root.shades[0]
                font.family: Style.font_family
                font.pixelSize: 8
            }
        }

        Item {
            id: body
            anchors.fill: parent
            anchors.margins: 12
            anchors.topMargin: 18
        }
    }

    component InfoLine: Row {
        id: info
        property string label: ""
        property string value: ""
        spacing: 6

        Text {
            width: 72
            text: info.label
            color: root.shades[2]
            font.family: Style.font_family
            font.pixelSize: 8
        }

        Text {
            text: info.value || "—"
            color: root.shades[3]
            font.family: Style.font_family
            font.pixelSize: 8
        }
    }

    TextMetrics {
        id: tab_metrics
        font.family: Style.font_family
        font.pixelSize: 16
        text: "TODAY"
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
                    id: day_tab
                    required property var modelData
                    required property int index
                    readonly property int day_index: root.first_day + day_tab.index
                    readonly property bool selected: day_tab.day_index === root.day_cursor

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: 28

                    PixelBox {
                        anchors.fill: parent
                        fill: day_tab.selected ? root.shades[3] : root.shades[0]
                        rings: day_tab.selected ? [root.shades[3]] : [root.shades[1]]
                    }

                    Text {
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 4)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: root.day_label(day_tab.day_index)
                        color: day_tab.selected ? root.shades[0] : root.shades[2]
                        font.family: Style.font_family
                        font.pixelSize: tab_metrics.advanceWidth <= day_tab.width - 6 ? 16 : 8
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(day_tab.day_index)
                    }
                }
            }
        }

        TitledBox {
            Layout.fillWidth: true
            implicitHeight: 124
            title: "CLOCK"

            Item {
                anchors.fill: parent

                Text {
                    id: period_word
                    text: root.is_today ? root.periods[root.period_index].name : root.day ? root.day.weekday.toUpperCase() : ""
                    color: root.shades[3]
                    font.family: Style.title_font_family
                    font.pixelSize: root.is_today ? 24 : 16
                }

                Text {
                    anchors.right: parent.right
                    anchors.baseline: period_word.baseline
                    text: root.is_today ? root.clock_text() : root.day ? root.day.date.substr(5).replace("-", "/") : ""
                    color: root.shades[2]
                    font.family: Style.font_family
                    font.pixelSize: 16
                }

                // Twenty-four hour cells: daylight lit, night dim, the live hour brightest with a caret over it.
                Item {
                    id: hours_bar
                    readonly property int cell: Math.max(4, Math.floor((parent.width - 23) / 24))
                    readonly property int bar_w: 24 * hours_bar.cell + 23
                    x: Math.round((parent.width - hours_bar.bar_w) / 2)
                    y: 44
                    width: hours_bar.bar_w
                    height: 12

                    Repeater {
                        model: 24

                        Rectangle {
                            required property int index
                            readonly property real mid: index * 60 + 30
                            readonly property bool daylight: root.has_sun && mid >= root.rise_minutes && mid < root.set_minutes
                            readonly property bool now_cell: root.is_today && Math.floor(root.now_minutes / 60) === index
                            x: index * (hours_bar.cell + 1)
                            width: hours_bar.cell
                            height: parent.height
                            color: now_cell ? root.shades[3] : daylight ? root.shades[2] : root.shades[1]
                        }
                    }

                    Text {
                        visible: root.is_today
                        x: Math.floor(root.now_minutes / 60) * (hours_bar.cell + 1) + Math.round((hours_bar.cell - width) / 2)
                        y: -14
                        text: "▼"
                        color: root.shades[3]
                        font.family: "Press Start 2P"
                        font.pixelSize: 8
                    }

                    Repeater {
                        model: root.periods

                        Rectangle {
                            id: period_tag
                            required property var modelData
                            required property int index
                            readonly property bool live: root.is_today && root.period_index === period_tag.index
                            x: period_tag.modelData.start * (hours_bar.cell + 1)
                            y: 16
                            width: tag_text.implicitWidth + 6
                            height: tag_text.implicitHeight + 2
                            color: period_tag.live ? root.shades[3] : "transparent"

                            Rectangle {
                                x: 0
                                y: -4
                                width: 2
                                height: 4
                                color: root.shades[2]
                            }

                            Text {
                                id: tag_text
                                anchors.centerIn: parent
                                text: period_tag.modelData.name
                                color: period_tag.live ? root.shades[0] : root.shades[2]
                                font.family: Style.font_family
                                font.pixelSize: 8
                            }
                        }
                    }
                }
            }
        }

        TextBox {
            Layout.fillWidth: true
            font_size: 16
            text: root.entry
        }

        TitledBox {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 110
            title: "MT.MOON"

            RowLayout {
                anchors.fill: parent
                spacing: 12

                PixelSprite {
                    Layout.alignment: Qt.AlignVCenter
                    pixel: 8
                    rows: PixelArt.moon_phase(root.moon_phase)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: WeatherState.moon_name(root.moon_phase).toUpperCase()
                        color: root.shades[3]
                        font.family: Style.font_family
                        font.pixelSize: 16
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.moon_flavour
                        color: root.shades[2]
                        font.family: Style.font_family
                        font.pixelSize: 8
                    }

                    InfoLine {
                        label: "MOONRISE"
                        value: root.moon_times.rise ? root.moon_times.rise.toUpperCase() : ""
                    }

                    InfoLine {
                        label: "MOONSET"
                        value: root.moon_times.set ? root.moon_times.set.toUpperCase() : ""
                    }

                    InfoLine {
                        label: "FULL MOON"
                        value: root.next_full.toUpperCase()
                    }
                }
            }
        }
    }
}
