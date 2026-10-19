pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.ui.gauges
import qs.theme
import qs.styles.reticle.widgets
import qs.features.weather
import qs.features.weather.views.shared
import qs.styles.metroid.widgets
import qs.features.popups

// One day as a Scan Visor readout: a hologram condition icon, the temperature range as a stack of Samus's
// energy tanks on the week's scale, and the rain chance as the missile counter.
// sub 1 to 3 swap the tanks for the wind, UV or sunshine reading: the dial and tanks fill from the bottom, the readout moves to the headline.
Item {
    id: root

    property var day: null
    property int day_index: 0
    property string label: ""
    property bool selected: false
    property real col_w: 0
    // The week's coldest low and warmest high, shared by every column so ranges compare across days.
    property real scale_min: 0
    property real scale_max: 1
    // 0 temperature range, 1 wind, 2 UV, 3 sunshine.
    property int sub: 0
    // The week's strongest gust, so wind columns compare across days.
    property real wind_max: 1

    readonly property bool has: !!root.day && root.day.max !== undefined
    readonly property int pop: root.has ? Math.round(root.day.pop || 0) : 0
    readonly property color visor: Style.pal.primary
    readonly property color visor_light: Style.pal.primary_light
    readonly property real inner_w: Math.max(10, root.width - 8)

    readonly property var uv_band_tags: ["LOW", "MOD", "HIGH", "V.HI", "EXT"]
    readonly property real daylight_hours: {
        if (!root.has) return 0;
        const rise = root.day.sunrise.split(":");
        const set = root.day.sunset.split(":");
        if (rise.length !== 2 || set.length !== 2) return 0;
        return Math.max(0, (parseInt(set[0], 10) * 60 + parseInt(set[1], 10) - parseInt(rise[0], 10) * 60 - parseInt(rise[1], 10)) / 60);
    }
    // How full the tank stack is on the non-temperature subs, and the colour it takes.
    readonly property real fill: {
        if (!root.has) return 0;
        if (root.sub === 1) return Math.min(1, root.day.wind_speed_max / Math.max(1, root.wind_max));
        if (root.sub === 2) return Math.min(1, root.day.uv_max / 12);
        return root.daylight_hours > 0 ? Math.min(1, root.day.sunshine_hours / root.daylight_hours) : 0;
    }
    readonly property real gust_fill: root.has && root.sub === 1 ? Math.min(1, root.day.wind_gusts_max / Math.max(1, root.wind_max)) : -1
    readonly property color fill_color: root.sub === 2 && root.has ? WeatherState.uv_color(root.day.uv_max) : root.sub === 3 ? Style.pal.yellow : root.visor_light
    readonly property string headline: {
        if (!root.has) return "";
        if (root.sub === 1) return String(Math.round(root.day.wind_speed_max));
        if (root.sub === 2) return root.day.uv_max.toFixed(1);
        if (root.sub === 3) return root.day.sunshine_hours.toFixed(1) + "h";
        return Math.round(root.day.max) + "°";
    }
    readonly property string footnote: {
        if (!root.has) return "";
        if (root.sub === 1) return "G" + Math.round(root.day.wind_gusts_max);
        if (root.sub === 2) return root.uv_band_tags[WeatherState.uv_bands.indexOf(WeatherState.uv_band(root.day.uv_max))];
        if (root.sub === 3) return Math.round(root.fill * 100) + "%";
        return Math.round(root.day.min) + "°";
    }

    function frac(v) {
        return Math.max(0, Math.min(1, (v - root.scale_min) / Math.max(0.01, root.scale_max - root.scale_min)));
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(root.visor, root.selected ? 0.07 : 0.025)
    }

    ScanLock {
        shown: root.selected && root.visible && Popups.open_name === "weather"
        visible: root.selected
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        anchors.topMargin: 8
        anchors.bottomMargin: 6
        spacing: 3
        opacity: root.selected ? 1 : 0.62

        Behavior on opacity {
            NumberAnimation {
                duration: 160
            }
        }

        Item {
            id: holo
            readonly property real size: Math.max(18, Math.min(40, root.inner_w - 12))
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: size
            Layout.preferredHeight: size
            clip: true

            Item {
                visible: root.sub === 1
                anchors.fill: parent

                Reticle {
                    anchors.fill: parent
                    color: Qt.alpha(root.visor_light, 0.7)
                }

                Text {
                    anchors.centerIn: parent
                    text: "▲"
                    rotation: root.has ? root.day.wind_dir : 0
                    color: root.visor_light
                    font.pixelSize: Math.round(holo.size * 0.4)
                }
            }

            WeatherIcon {
                id: holo_icon
                visible: root.sub !== 1
                anchors.fill: parent
                size: holo.size
                code: root.has ? root.day.code : 0
                opacity: 0.9
            }

            // A short flicker every few seconds and one scanline sweeping the selected day's hologram.
            SequentialAnimation {
                running: root.selected && root.visible
                loops: Animation.Infinite
                onRunningChanged: if (!running) holo_icon.opacity = 0.9

                PauseAnimation { duration: 2600 }
                NumberAnimation { target: holo_icon; property: "opacity"; to: 0.55; duration: 50 }
                NumberAnimation { target: holo_icon; property: "opacity"; to: 0.9; duration: 70 }
                NumberAnimation { target: holo_icon; property: "opacity"; to: 0.7; duration: 40 }
                NumberAnimation { target: holo_icon; property: "opacity"; to: 0.9; duration: 90 }
            }

            Rectangle {
                visible: root.selected
                width: parent.width
                height: 1
                color: Qt.alpha(root.visor_light, 0.55)

                NumberAnimation on y {
                    running: root.selected && root.visible
                    loops: Animation.Infinite
                    from: 0
                    to: holo.size
                    duration: 1800
                }
            }
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.headline
            color: root.sub === 2 || root.sub === 3 ? root.fill_color : Style.pal.fg_strong
            font.family: Style.number_font
            font.pixelSize: Style.fs(-2)
        }

        Item {
            id: tank_area
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 30

            readonly property real gap: 3
            readonly property int count: Math.max(4, Math.min(14, Math.floor((height + gap) / 15)))
            readonly property real step: (height + gap) / count
            readonly property real tank_size: Math.max(5, Math.min(18, root.inner_w * 0.4, step - gap))
            readonly property bool ranged: root.sub === 0
            readonly property int first_lit: !root.has ? count : ranged ? Math.min(count - 1, Math.floor(root.frac(root.day.min) * count)) : 0
            // At least the low's own tank stays lit, so a day with no spread still shows where it sits.
            readonly property int last_lit: !root.has ? -1 : ranged ? Math.max(first_lit, Math.min(count - 1, Math.ceil(root.frac(root.day.max) * count) - 1)) : Math.ceil(root.fill * count) - 1
            readonly property int gust_tank: root.gust_fill < 0 ? -1 : Math.min(count - 1, Math.max(0, Math.ceil(root.gust_fill * count) - 1))

            Repeater {
                model: tank_area.count

                Rectangle {
                    required property int index
                    readonly property bool lit: index >= tank_area.first_lit && index <= tank_area.last_lit

                    width: tank_area.tank_size
                    height: tank_area.tank_size
                    x: (tank_area.width - width) / 2
                    y: tank_area.height - index * tank_area.step - tank_area.step / 2 - height / 2 + tank_area.gap / 2
                    radius: Math.min(3, width / 4)
                    // On the wind sub the tank at the day's strongest gust shows as a lone lit cell above the sustained speed.
                    readonly property bool gust: index === tank_area.gust_tank && index > tank_area.last_lit
                    readonly property color tone: tank_area.ranged ? root.visor_light : root.fill_color
                    color: lit ? (root.selected || !tank_area.ranged ? tone : root.visor) : "transparent"
                    border.width: 1
                    border.color: lit || gust ? Qt.alpha(tone, 0.9) : Qt.alpha(root.visor, 0.3)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.footnote
            color: Style.text_muted
            font.family: Style.number_font
            font.pixelSize: Style.fs(-3)
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 2
            color: Qt.alpha(root.visor, 0.3)
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 3

            Item {
                id: missile
                anchors.verticalCenter: parent.verticalCenter
                width: 13
                height: 6
                readonly property color tone: root.pop > 0 ? root.visor_light : Qt.alpha(root.visor, 0.4)

                Rectangle {
                    x: 2
                    y: 1
                    width: 8
                    height: 4
                    color: missile.tone
                }

                Rectangle {
                    width: 3
                    height: 6
                    color: missile.tone
                }

                Rectangle {
                    x: 8
                    y: 1
                    width: 4
                    height: 4
                    rotation: 45
                    color: missile.tone
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // Zero-padded to three digits like the missile counter.
                text: String(root.pop).padStart(3, "0")
                color: root.pop > 0 ? Style.pal.fg_strong : Style.text_muted
                font.family: Style.number_font
                font.pixelSize: Style.fs(-4)
            }
        }

        SegBar {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            Layout.preferredHeight: 3
            count: 5
            gap: 2
            last_lit: Math.ceil(root.pop / 20) - 1
            on_color: root.visor_light
            off_color: Qt.alpha(root.visor, 0.18)
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 3
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.label.toUpperCase()
            color: root.selected ? root.visor_light : root.visor
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
            font.letterSpacing: root.inner_w >= 50 ? 1.5 : 0
        }
    }
}
