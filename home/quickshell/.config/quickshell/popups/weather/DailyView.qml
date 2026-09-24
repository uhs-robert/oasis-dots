// home/quickshell/.config/quickshell/popups/weather/DailyView.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../services"

// One column per day in a window of up to five that the popup scrolls with day_cursor.
// sub 0: temp band + precip chance. 1: wind. 2: UV. 3: sunshine.
Item {
    id: root

    property int day_cursor: 0
    property int first_day: 0
    property int sub: 0
    // Called with the clicked day index; the popup owns day_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property var sub_names: ["Temp & Precip", "Wind", "UV", "Sunshine"]

    FontMetrics {
        id: label_metrics
        font.family: Style.font_family
        font.pixelSize: Style.font_size - 2
    }

    // Columns that fit without clipping their widest label, capped at five.
    readonly property int fit_days: {
        const f = label_metrics.font;
        const col = Math.max(label_metrics.advanceWidth("Today"), label_metrics.advanceWidth("100%")) + 8;
        return Math.max(1, Math.min(5, Math.floor((root.width + 4) / (col + 4))));
    }
    readonly property var window_days: WeatherState.days.slice(root.first_day, root.first_day + root.fit_days)

    readonly property int bar_area_h: 170
    readonly property int headroom: 18
    readonly property int footroom: 18
    readonly property int band_range_h: root.bar_area_h - root.headroom - root.footroom
    readonly property int icon_size: 64

    readonly property var week_temp_range: {
        const days = WeatherState.days;
        if (!days || days.length === 0) return { min: 0, max: 1 };
        let lo = Math.min(...days.map(d => d.min));
        let hi = Math.max(...days.map(d => d.max));
        if (hi <= lo) hi = lo + 1;
        const pad = Math.max(1, (hi - lo) * 0.12);
        return { min: lo - pad, max: hi + pad };
    }

    function inner_top_y(day) {
        const r = root.week_temp_range;
        return root.headroom + (r.max - day.max) / (r.max - r.min) * root.band_range_h;
    }

    function inner_bottom_y(day) {
        const r = root.week_temp_range;
        return root.headroom + (r.max - day.min) / (r.max - r.min) * root.band_range_h;
    }

    readonly property real wind_max: {
        const days = WeatherState.days;
        if (!days || days.length === 0) return 1;
        return Math.max(1, ...days.map(d => d.wind_gusts_max));
    }

    function fmt_temp(t) {
        return Math.round(t) + "°" + WeatherState.unit_symbol();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4

            Repeater {
                model: root.window_days

                Item {
                    id: day_col
                    required property var modelData
                    required property int index
                    readonly property int day_index: root.first_day + day_col.index

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: Style.radius(4)
                        color: Theme.bg_surface
                        visible: day_col.day_index === root.day_cursor
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(day_col.day_index)
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 2
                        spacing: 2

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredHeight: root.bar_area_h
                            visible: root.sub === 0

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.55
                                radius: Style.radius(2)
                                color: Theme.blue
                                opacity: 0.35
                                height: (Math.max(0, Math.min(100, day_col.modelData.pop)) / 100) * parent.height
                            }

                            Rectangle {
                                id: inner_band
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.3
                                radius: Style.radius(2)
                                color: Style.chart_fill
                                y: root.inner_top_y(day_col.modelData)
                                height: Math.max(4, root.inner_bottom_y(day_col.modelData) - root.inner_top_y(day_col.modelData))
                                antialiasing: Style.chart_slant > 0
                                transform: Matrix4x4 {
                                    matrix: Qt.matrix4x4(1, -Style.chart_slant, 0, Style.chart_slant * inner_band.height / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: inner_band.y - implicitHeight - 1
                                text: Math.round(day_col.modelData.max) + "°"
                                color: Theme.yellow
                                font.family: Style.font_family
                                font.pixelSize: Style.font_size - 3
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: inner_band.y + inner_band.height + 1
                                text: Math.round(day_col.modelData.min) + "°"
                                color: Theme.yellow
                                font.family: Style.font_family
                                font.pixelSize: Style.font_size - 3
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredHeight: root.bar_area_h
                            visible: root.sub === 1

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                text: "▲"
                                rotation: day_col.modelData.wind_dir
                                color: Theme.cyan
                                font.pixelSize: Style.font_size - 3
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.5
                                radius: Style.radius(2)
                                color: Theme.cyan
                                opacity: 0.5
                                height: (day_col.modelData.wind_speed_max / root.wind_max) * (parent.height - 36)
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.6
                                height: 2
                                color: Theme.bright_cyan
                                y: parent.height - (day_col.modelData.wind_gusts_max / root.wind_max) * (parent.height - 36)
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: Math.max(16, parent.height - (day_col.modelData.wind_gusts_max / root.wind_max) * (parent.height - 36) - 18)
                                text: Math.round(day_col.modelData.wind_speed_max)
                                color: Theme.cyan
                                font.family: Style.font_family
                                font.pixelSize: Style.font_size - 3
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredHeight: root.bar_area_h
                            visible: root.sub === 2

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.5
                                radius: Style.radius(2)
                                color: WeatherState.uv_color(day_col.modelData.uv_max)
                                opacity: 0.7
                                height: Math.min(1, day_col.modelData.uv_max / 12) * (parent.height - 18)
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: parent.height - Math.min(1, day_col.modelData.uv_max / 12) * (parent.height - 18) - 16
                                text: day_col.modelData.uv_max.toFixed(1)
                                color: WeatherState.uv_color(day_col.modelData.uv_max)
                                font.family: Style.font_family
                                font.pixelSize: Style.font_size - 3
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredHeight: root.bar_area_h
                            visible: root.sub === 3

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.5
                                radius: Style.radius(2)
                                color: Theme.yellow
                                opacity: 0.55
                                height: Math.min(1, day_col.modelData.sunshine_hours / 14) * (parent.height - 18)
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: parent.height - Math.min(1, day_col.modelData.sunshine_hours / 14) * (parent.height - 18) - 16
                                text: day_col.modelData.sunshine_hours.toFixed(1) + "h"
                                color: Theme.yellow
                                font.family: Style.font_family
                                font.pixelSize: Style.font_size - 3
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: day_col.modelData.pop + "%"
                            color: Theme.blue
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size - 2
                        }

                        Item {
                            id: icon_box
                            readonly property real size: Math.max(16, Math.min(root.icon_size, day_col.width - 4))
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: icon_box.size
                            Layout.preferredHeight: icon_box.size

                            Image {
                                anchors.centerIn: parent
                                width: icon_box.size
                                height: icon_box.size
                                readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                                sourceSize.width: Math.ceil(root.icon_size * 2 * dpr)
                                sourceSize.height: Math.ceil(root.icon_size * 2 * dpr)
                                source: WeatherState.icon_source(day_col.modelData.code, true)
                                smooth: true
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: day_col.modelData.weekday
                            color: day_col.day_index === root.day_cursor ? Theme.theme_secondary : Theme.fg_core
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size - 2
                        }
                    }
                }
            }
        }

        // Chevrons mark days outside the window; h/l scroll to them.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 4

            Text {
                opacity: root.first_day > 0 ? 1 : 0
                text: "‹"
                color: Theme.theme_secondary
                font.family: Style.font_family
                font.pixelSize: Style.font_size
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                readonly property var selected: WeatherState.days[root.day_cursor]
                text: selected ? selected.cond + " · " + selected.precip.toFixed(2) + (WeatherState.settings.unit === "celsius" ? " mm" : " in") + " · " + (selected.sunrise || "—") + "–" + (selected.sunset || "—") : ""
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.font_size - 3
            }

            Text {
                opacity: root.first_day + root.fit_days < WeatherState.days.length ? 1 : 0
                text: "›"
                color: Theme.theme_secondary
                font.family: Style.font_family
                font.pixelSize: Style.font_size
            }
        }
    }
}
