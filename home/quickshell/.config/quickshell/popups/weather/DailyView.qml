// home/quickshell/.config/quickshell/popups/weather/DailyView.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../../theme"
import "../../services"
import "../../components/oasis" as Oasis
import "../../components/modern" as Modern

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
    // Game Boy: days as a Game Boy Camera photo strip on the week's hi/lo dot scale.
    readonly property bool camera: Style.weather_header === "pokedex" && root.sub === 0
    // Oasis: range pills over a horizon of weekday names, the selected day rising in sand.
    readonly property bool dunes: Style.weather_header === "oasis" && root.sub === 0
    // Modern: raised day columns with a pill label and a range track.
    readonly property bool pill_columns: Style.weather_header === "hero" && root.sub === 0
    readonly property bool custom_column: root.ws_panels || root.tower_columns || root.camera || root.dunes || root.pill_columns
    // NES: each column in a Dragon Quest window with a cursor on the selected day.
    readonly property bool dq: Style.weather_header === "battle"
    // SNES: columns standing on a Mode 7 floor.
    readonly property bool mode7: Style.weather_header === "mode7"
    readonly property bool floor_shown: root.mode7 && root.visible && Popups.open_name === "weather"
    // Terminal: `curl wttr.in`, the window as one box-drawn table.
    readonly property bool wttr_table: Style.weather_header === "wttr" && root.sub === 0
    // Half-Life: HL1 weapon-slot buckets, the selected day open wider.
    readonly property bool hev_slots: Style.weather_header === "hev" && root.sub === 0
    // FF7: the days as linked materia slots.
    readonly property bool materia_slots: Style.weather_header === "status" && root.sub === 0
    // Views that draw the whole window themselves instead of the day row.
    readonly property bool row_replaced: root.wttr_table || root.hev_slots || root.materia_slots

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
        font.pixelSize: Style.fs(-2)
    }

    FontMetrics {
        id: table_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
    }

    FontMetrics {
        id: small_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
    }

    // Columns that fit without clipping their widest label, capped at five.
    readonly property int fit_days: {
        const f = [label_metrics.font, table_metrics.font];
        const mission_w = root.mission ? Math.max(label_metrics.advanceWidth("a) WED"), small_metrics.advanceWidth("PROGRESS") + 8) : 0;
        const dq_w = root.dq ? 2 * (small_metrics.advanceWidth(Style.row_cursor) + 3) : 0;
        if (root.hev_slots) return Math.max(1, Math.min(5, 1 + Math.floor((root.width - 100) / 52)));
        const col = Style.weather_header === "wttr" ? table_metrics.advanceWidth("─") * 8 - 4
            : Style.weather_header === "status" ? Math.max(table_metrics.advanceWidth("Today"), table_metrics.advanceWidth("100%"), 44) + 6
            : root.dq ? Math.max(label_metrics.advanceWidth("100%"), label_metrics.advanceWidth("WED") + dq_w) + 16
            // Room for a 3x-scale 24x18 photo (72x54) plus its frame.
            : root.camera ? 24 * 3 + 18 + 8
            : Math.max(label_metrics.advanceWidth("Today"), label_metrics.advanceWidth("100%"), mission_w) + 8;
        // Reserve room for the row-label column ("RAIN" is the widest), matching MateriaSlots' own label_w.
        const status_label_w = Math.max(40, small_metrics.advanceWidth("RAIN") + 12);
        const room = Style.weather_header === "status" ? root.width - status_label_w : root.width + 4;
        return Math.max(1, Math.min(5, Math.floor(room / (col + 4))));
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

    // Oasis scales its floating bars to the days in view, so the warmest sits right under its icon.
    readonly property var window_temp_range: {
        const days = root.window_days;
        if (!days || days.length === 0) return { min: 0, max: 1 };
        const lo = Math.min(...days.map(d => d.min));
        const hi = Math.max(...days.map(d => d.max));
        return { min: lo, max: Math.max(hi, lo + 1) };
    }

    function inner_top_y(day) {
        const r = root.week_temp_range;
        return root.headroom + (r.max - day.max) / (r.max - r.min) * root.band_range_h;
    }

    function inner_bottom_y(day) {
        const r = root.week_temp_range;
        return root.headroom + (r.max - day.min) / (r.max - r.min) * root.band_range_h;
    }

    readonly property real week_low: WeatherState.days.length > 0 ? Math.min(...WeatherState.days.map(d => d.min)) : 0
    readonly property real week_high: WeatherState.days.length > 0 ? Math.max(...WeatherState.days.map(d => d.max)) : 1

    readonly property real wind_max: {
        const days = WeatherState.days;
        if (!days || days.length === 0) return 1;
        return Math.max(1, ...days.map(d => d.wind_gusts_max));
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
            color: Style.pal.secondary
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
            style: Text.Outline
            styleColor: Style.pal.bg_shadow
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

        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            active: root.hev_slots
            visible: active
            sourceComponent: WeaponSlots {
                days: root.window_days
                first_day: root.first_day
                day_cursor: root.day_cursor
                on_select: root.on_select
            }
        }

        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            active: root.materia_slots
            visible: active
            sourceComponent: MateriaSlots {
                days: root.window_days
                first_day: root.first_day
                day_cursor: root.day_cursor
                on_select: root.on_select
            }
        }

        RowLayout {
            id: day_row
            visible: !root.row_replaced
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
                        color: Qt.alpha(Style.pal.bg_shadow, 0.7)
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
                        color: Style.range_line ? "transparent" : Style.selection_brackets.a > 0 || root.mission || root.mode7 ? Style.selection_bg : Style.pal.bg_surface
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
                        active: root.camera
                        anchors.fill: parent
                        sourceComponent: CameraPhoto {
                            day: day_col.modelData
                            day_index: day_col.day_index
                            selected: day_col.day_index === root.day_cursor
                            scale_min: root.week_low
                            scale_max: root.week_high
                            slot_w: Math.floor((day_row.width - day_row.spacing * (root.window_days.length - 1)) / Math.max(1, root.window_days.length))
                        }
                    }

                    Loader {
                        active: root.dunes
                        anchors.fill: parent
                        sourceComponent: Oasis.OasisDay {
                            day: day_col.modelData
                            selected: day_col.day_index === root.day_cursor
                            scale_min: root.window_temp_range.min
                            scale_max: root.window_temp_range.max
                            first: day_col.index === 0
                            last: day_col.index === root.window_days.length - 1
                            bleed: day_row.spacing / 2
                        }
                    }

                    Loader {
                        active: root.pill_columns
                        anchors.fill: parent
                        sourceComponent: Modern.DayColumn {
                            day: day_col.modelData
                            label: root.day_label(day_col.modelData, day_col.day_index)
                            selected: day_col.day_index === root.day_cursor
                            scale_min: root.week_temp_range.min
                            scale_max: root.week_temp_range.max
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

                    DayBars {
                        visible: !root.custom_column
                        anchors.fill: parent
                        day: day_col.modelData
                        day_index: day_col.day_index
                        selected: day_col.day_index === root.day_cursor
                        sub: root.sub
                        label: root.day_label(day_col.modelData, day_col.day_index)
                        col_w: day_col.width
                        dq: root.dq
                        mission: root.mission
                        save_blocks: root.save_blocks
                        ladder: root.ladder
                        thin_range: root.thin_range
                        bar_area_h: root.bar_area_h
                        icon_size: root.icon_size
                        wind_max: root.wind_max
                        top_y: root.inner_top_y(day_col.modelData)
                        bottom_y: root.inner_bottom_y(day_col.modelData)
                    }
                }
            }
        }

        RowLayout {
            visible: root.camera && root.window_days.length > 0
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: "HI LO °" + WeatherState.unit_symbol() + " · RAIN %"
                color: Style.pixel_shades[2]
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }

            Text {
                text: Math.round(root.week_low) + "–" + Math.round(root.week_high) + "°" + WeatherState.unit_symbol()
                color: Style.pixel_shades[2]
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
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
                color: Style.pal.secondary
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
                text: selected ? selected.cond + " · " + selected.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in") + " · " + (WeatherState.fmt_hm(selected.sunrise) || "—") + "–" + (WeatherState.fmt_hm(selected.sunset) || "—") : ""
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }

            Text {
                opacity: root.first_day + root.fit_days < WeatherState.days.length ? 1 : 0
                text: "›"
                color: Style.pal.secondary
                font.family: Style.font_family
                font.pixelSize: Style.font_size
            }
        }
    }
}
