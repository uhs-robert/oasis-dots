// home/quickshell/.config/quickshell/popups/weather/DailyView.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
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
    readonly property bool stat_columns: Style.weather_header === "spec" && root.sub === 0
    // Temperature ranges as 1px altitude ladders with rungs.
    readonly property bool ladder: Style.weather_header === "scope"
    readonly property bool thin_range: Style.range_line || root.ladder
    // GoldenEye: a mission line over the columns, each lettered as an objective.
    readonly property bool mission: Style.weather_header === "watch"
    // PS1: each column headed by its memory card save block in place of the icon.
    readonly property bool save_blocks: Style.weather_header === "memcard"
    // CRT: WeatherStar 4000 "Extended Forecast" panels.
    readonly property bool ws_panels: Style.weather_header === "weatherstar" && root.sub === 0
    // PS2: days as translucent towers on a dark floor.
    readonly property bool tower_columns: Style.weather_header === "towers" && root.sub === 0
    readonly property int tower_labels_h: Math.round(Style.font_size * 3.4)
    // Metroid: scan brackets lock onto the selected day.
    readonly property bool scan: Style.weather_header === "scan"
    readonly property bool custom_column: root.stat_columns || root.ws_panels || root.tower_columns
    // NES: each column in a Dragon Quest window with a cursor on the selected day.
    readonly property bool dq: Style.weather_header === "battle"
    // SNES: columns standing on a Mode 7 floor.
    readonly property bool mode7: Style.weather_header === "mode7"
    readonly property bool floor_shown: root.mode7 && root.visible && Popups.open_name === "weather"
    // Terminal: `curl wttr.in`, the window as one box-drawn table.
    readonly property bool wttr_table: Style.weather_header === "wttr" && root.sub === 0

    onFloor_shownChanged: {
        if (!floor_loader.item) return;
        if (root.floor_shown) floor_loader.item.run();
        else floor_loader.item.stop();
    }

    function day_label(day, i) {
        const ddd = Qt.formatDate(new Date(day.date + "T00:00:00"), "ddd").toUpperCase();
        if (root.mission) return String.fromCharCode(97 + i) + ") " + ddd;
        if (root.dq) return i === 0 ? "NOW" : ddd;
        return day.weekday;
    }

    FontMetrics {
        id: label_metrics
        font.family: Style.font_family
        font.pixelSize: Style.font_size - 2
    }

    FontMetrics {
        id: table_metrics
        font.family: Style.font_family
        font.pixelSize: Style.font_size - 4
    }

    FontMetrics {
        id: small_metrics
        font.family: Style.font_family
        font.pixelSize: Style.font_size - 5
    }

    // Columns that fit without clipping their widest label, capped at five.
    readonly property int fit_days: {
        const f = [label_metrics.font, table_metrics.font];
        const mission_w = root.mission ? Math.max(label_metrics.advanceWidth("a) WED"), small_metrics.advanceWidth("PROGRESS") + 8) : 0;
        const dq_w = root.dq ? 2 * (small_metrics.advanceWidth(Style.row_cursor) + 3) : 0;
        const col = root.stat_columns ? 56
            : Style.weather_header === "wttr" ? table_metrics.advanceWidth("─") * 8 - 4
            : root.dq ? Math.max(label_metrics.advanceWidth("100%"), label_metrics.advanceWidth("WED") + dq_w) + 16
            : Math.max(label_metrics.advanceWidth("Today"), label_metrics.advanceWidth("100%"), mission_w) + 8;
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

    Loader {
        id: floor_loader
        active: root.mode7
        x: day_row.x
        y: day_row.y + day_row.height * 0.42
        width: day_row.width
        height: day_row.height * 0.58
        sourceComponent: Mode7Floor {}
        onLoaded: if (root.floor_shown) floor_loader.item.run()
    }

    Loader {
        active: root.tower_columns && root.window_days.length > 0
        x: day_row.x - 2
        y: day_row.y + day_row.height - root.tower_labels_h - 40
        width: day_row.width + 4
        height: root.tower_labels_h + 40
        sourceComponent: TowerFloor {
            haze_h: 40
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        Loader {
            Layout.fillWidth: true
            active: root.mission
            visible: active
            sourceComponent: MissionHeader {}
        }

        Text {
            visible: root.ws_panels && root.window_days.length > 0
            text: "Extended Forecast"
            color: Theme.theme_secondary
            font.family: Style.font_family
            font.pixelSize: Style.font_size - 3
            style: Text.Outline
            styleColor: Theme.bg_shadow
        }

        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            active: root.wttr_table
            visible: active
            sourceComponent: WttrTable {
                days: root.window_days
                first_day: root.first_day
                day_cursor: root.day_cursor
                scale_min: root.week_temp_range.min
                scale_max: root.week_temp_range.max
                on_select: root.on_select
            }
        }

        RowLayout {
            id: day_row
            visible: !root.wttr_table
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
                    transformOrigin: Item.Bottom
                    scale: root.mode7 && day_col.day_index !== root.day_cursor ? 0.93 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: 120
                        }
                    }

                    Rectangle {
                        visible: root.mode7
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -5
                        width: parent.width * 0.8
                        height: 8
                        radius: 4
                        color: Qt.alpha(Theme.bg_shadow, 0.7)
                    }

                    Loader {
                        active: root.dq
                        anchors.fill: parent
                        anchors.margins: 0
                        sourceComponent: DqWindow {}
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: Style.radius(4)
                        color: Style.range_line ? "transparent" : Style.selection_brackets.a > 0 || root.mission || root.mode7 ? Style.selection_bg : Theme.bg_surface
                        border.width: Style.range_line ? 1 : 0
                        border.color: Style.hairline_dim
                        visible: day_col.day_index === root.day_cursor && !root.custom_column && !root.dq

                        LockBrackets {}

                        Loader {
                            active: root.scan
                            anchors.fill: parent
                            sourceComponent: ScanLock {
                                shown: day_col.day_index === root.day_cursor && root.visible && Popups.open_name === "weather"
                            }
                        }

                        Rectangle {
                            visible: root.mission
                            width: parent.width
                            height: 2
                            color: Style.caret_color
                        }
                    }

                    Loader {
                        active: root.stat_columns
                        anchors.fill: parent
                        sourceComponent: DayStatColumn {
                            day: day_col.modelData
                            day_index: day_col.day_index
                            selected: day_col.day_index === root.day_cursor
                            scale_min: root.week_temp_range.min
                            scale_max: root.week_temp_range.max
                        }
                    }

                    Loader {
                        active: root.tower_columns
                        anchors.fill: parent
                        sourceComponent: TowerColumn {
                            day: day_col.modelData
                            selected: day_col.day_index === root.day_cursor
                            scale_min: root.week_temp_range.min
                            scale_max: root.week_temp_range.max
                            labels_h: root.tower_labels_h
                        }
                    }

                    Loader {
                        active: root.ws_panels
                        anchors.fill: parent
                        sourceComponent: WsDayPanel {
                            day: day_col.modelData
                            selected: day_col.day_index === root.day_cursor
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(day_col.day_index)
                    }

                    ColumnLayout {
                        visible: !root.custom_column
                        anchors.fill: parent
                        anchors.margins: root.dq ? 8 : 2
                        spacing: 2

                        SaveBlock {
                            visible: root.save_blocks
                            Layout.alignment: Qt.AlignHCenter
                            block_size: Math.max(24, Math.min(48, day_col.width - 8))
                            day: day_col.modelData
                            selected: day_col.day_index === root.day_cursor
                        }

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
                                width: root.thin_range ? 1 : parent.width * 0.3
                                radius: Style.radius(2)
                                color: root.ladder ? (day_col.day_index === root.day_cursor ? Style.selection_brackets : Style.text_primary) : !Style.range_line ? Style.chart_fill : day_col.day_index === root.day_cursor ? Style.text_accent : Style.text_strong
                                border.width: Style.chart_outline.a > 0 && !root.ladder ? 1 : 0
                                border.color: Style.chart_outline
                                y: root.inner_top_y(day_col.modelData)
                                height: Math.max(4, root.inner_bottom_y(day_col.modelData) - root.inner_top_y(day_col.modelData))
                                antialiasing: Style.chart_slant > 0
                                transform: Matrix4x4 {
                                    matrix: Qt.matrix4x4(1, -Style.chart_slant, 0, Style.chart_slant * inner_band.height / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                                }

                                RangeCaps {
                                    visible: Style.range_line
                                }

                                Repeater {
                                    id: rungs
                                    readonly property int steps: Math.max(1, Math.round(inner_band.height / 6))
                                    model: root.ladder ? rungs.steps + 1 : 0

                                    Rectangle {
                                        required property int index
                                        readonly property bool major: index === 0 || index === rungs.steps
                                        width: major ? 11 : 5
                                        height: 1
                                        x: (1 - width) / 2
                                        y: Math.min(inner_band.height - 1, index * inner_band.height / rungs.steps)
                                        color: inner_band.color
                                        opacity: major ? 1 : 0.5
                                    }
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: inner_band.y - implicitHeight - (root.thin_range ? 5 : 1)
                                text: Math.round(day_col.modelData.max) + "°"
                                color: root.thin_range ? Style.text_strong : Theme.yellow
                                font.family: Style.font_family
                                font.pixelSize: Style.font_size - 3
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: inner_band.y + inner_band.height + (root.thin_range ? 5 : 1)
                                text: Math.round(day_col.modelData.min) + "°"
                                color: root.thin_range ? Style.text_muted : Theme.yellow
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
                            visible: !root.save_blocks
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
                            id: day_name
                            text: root.day_label(day_col.modelData, day_col.day_index)
                            color: root.dq ? Theme.fg_strong : day_col.day_index === root.day_cursor ? Theme.theme_secondary : Theme.fg_core
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size - 2

                            Text {
                                visible: root.dq && day_col.day_index === root.day_cursor && Style.caret_phase
                                anchors.right: parent.horizontalCenter
                                anchors.rightMargin: day_name.contentWidth / 2 + 3
                                anchors.verticalCenter: parent.verticalCenter
                                text: Style.row_cursor
                                color: Style.caret_color
                                font.family: Style.font_family
                                font.pixelSize: Style.font_size - 5
                            }
                        }

                        Text {
                            visible: root.mission
                            opacity: day_col.day_index === 0 ? 1 : 0
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: "IN PROGRESS"
                            color: Style.accent_color
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size - 5
                            font.letterSpacing: 1
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
