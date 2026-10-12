// home/quickshell/.config/quickshell/popups/weather/CameraPhoto.qml
import QtQuick
import "../../components"
import "../../theme"
import "../../services"
import "PixelArt.js" as PixelArt

// One day as a framed Game Boy Camera photo with its hi/lo dot bar, temperatures and rain chance.
Item {
    id: root

    property var day: null
    property int day_index: 0
    property bool selected: false
    property real scale_min: 0
    property real scale_max: 1
    // 0 temp, 1 wind, 2 UV, 3 sunshine; the photo stays and the stats under it change.
    property int sub: 0
    property real wind_max: 1
    // Narrowest column width in the strip, so every photo picks the same scale.
    property real slot_w: root.width

    // Three 2px selection rings plus 4px inner padding, reserved even unselected so sizing never jumps.
    readonly property int box_pad: 10
    readonly property real avail_w: root.slot_w - 2 * root.box_pad
    readonly property real avail_h: root.height - 2 * root.box_pad

    // Silkscreen sits on an 8px grid, so step up by whole grid units while the widest label and temp pair still fit.
    readonly property int text_size: {
        for (const size of [32, 24]) {
            if (Math.max(root.label_w(size), root.temp_w(size)) <= root.avail_w - 2 && root.avail_h >= 6 * size + 110) return size;
        }
        return Style.font_size;
    }
    // The high reads one grid step larger when a single stacked temperature has the width for it.
    readonly property int hi_size: root.text_size < 32 && root.temp_w(root.text_size + 8) <= root.avail_w - 2 ? root.text_size + 8 : root.text_size
    // Rough label/temp/pop row height, used only to budget the sprite scale; the real gap is filled below.
    readonly property real text_row_h: root.text_size + 6
    readonly property int width_pixel: Math.max(1, Math.floor((root.avail_w - 18) / 24))
    readonly property int height_pixel: Math.max(1, Math.floor((root.avail_h - 4 * root.text_row_h - 46) / 20))
    // Largest integer scale of the 24x18 photo that fits both the column width and the available height.
    readonly property int pixel: Math.max(1, Math.min(6, Math.min(root.width_pixel, root.height_pixel)))

    // One-shot hop offset applied to the photo frame when the selection lands here; never loops.
    property int hop_offset: 0

    onSelectedChanged: {
        if (root.selected && Popups.open_name === "weather") hop_anim.restart();
    }

    Connections {
        target: Popups
        function onOpen_nameChanged() {
            if (Popups.open_name !== "weather") hop_anim.stop();
        }
    }

    SequentialAnimation {
        id: hop_anim
        PropertyAction { target: root; property: "hop_offset"; value: -4 }
        PauseAnimation { duration: 100 }
        PropertyAction { target: root; property: "hop_offset"; value: -2 }
        PauseAnimation { duration: 100 }
        PropertyAction { target: root; property: "hop_offset"; value: 0 }
    }

    // Space left over after the photo, dot bar and labels take their natural size, spread across the gaps between them.
    readonly property real content_h: label_row.height + photo_box.height + (root.sub === 0 ? dot_bar.height + temp_row.height + pop_text.height : stat_col.height + (foot_text.visible ? foot_text.height : 0))
    readonly property real fill_spacing: Math.max(3, (root.avail_h - root.content_h) / (root.sub === 0 ? 4 : foot_text.visible ? 3 : 2))
    readonly property int value_size: Math.min(root.text_size, 24)

    // Each stat is a name, a value with its unit and a bar on its own scale; the foot line carries direction, band or daylight share.
    // The bands' full names overrun a narrow column at pixel-font size.
    readonly property var band_names: ["LOW", "MOD", "HIGH", "V.HIGH", "EXTRM"]
    readonly property var stats: {
        const d = root.day;
        if (!d) return [];
        if (root.sub === 1) return [
            { name: "SPD", value: String(Math.round(d.wind_speed_max)), unit: WeatherState.wind_unit().toUpperCase(), fill: d.wind_speed_max / root.wind_max },
            { name: "GUST", value: String(Math.round(d.wind_gusts_max)), unit: "", fill: d.wind_gusts_max / root.wind_max }
        ];
        if (root.sub === 2) {
            const bands = WeatherState.uv_bands;
            const band = WeatherState.uv_band(d.uv_max);
            return [
                { name: "UV", value: d.uv_max.toFixed(1), unit: "", fill: d.uv_max / 11 },
                { name: "BAND", value: root.band_names[bands.indexOf(band)], unit: "", fill: (bands.indexOf(band) + 1) / bands.length, small: true }
            ];
        }
        if (root.sub === 3) return [
            { name: "SUN", value: d.sunshine_hours.toFixed(1), unit: "H", fill: d.sunshine_hours / 14 },
            { name: "OF DAY", value: root.daylight_share + "%", unit: "", fill: root.daylight_share / 100 }
        ];
        return [];
    }
    readonly property string foot: {
        const d = root.day;
        if (!d) return "";
        if (root.sub === 1) return WeatherState.compass_label(d.wind_dir);
        if (root.sub !== 3) return "";
        const mins = root.daylight_minutes;
        return mins > 0 ? Math.floor(mins / 60) + "H" + String(mins % 60).padStart(2, "0") : "";
    }
    readonly property int daylight_minutes: root.day ? root.minutes_of(root.day.sunset) - root.minutes_of(root.day.sunrise) : 0
    readonly property int daylight_share: root.daylight_minutes > 0 ? Math.round(Math.min(1, root.day.sunshine_hours * 60 / root.daylight_minutes) * 100) : 0

    function minutes_of(hm: string): int {
        const parts = (hm || "").split(":");
        return parts.length === 2 ? parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10) : -1;
    }

    function label_w(size: int): real {
        return arrow_metrics.advanceWidth + 2 + (size === 32 ? label_32.advanceWidth : label_24.advanceWidth);
    }

    function temp_w(size: int): real {
        return (size === 32 ? temp_32.advanceWidth : size === 24 ? temp_24.advanceWidth : 0) + Math.max(3, Math.round(size / 4)) + 2;
    }

    TextMetrics { id: arrow_metrics; font.family: Style.font_family; font.pixelSize: Style.font_size; text: "▶" }
    TextMetrics { id: label_24; font.family: Style.font_family; font.pixelSize: 24; text: "TODAY" }
    TextMetrics { id: label_32; font.family: Style.font_family; font.pixelSize: 32; text: "TODAY" }
    // The week's extremes share one scale across columns, so every photo picks the same size.
    readonly property string widest_temp: {
        const a = String(Math.round(root.scale_min)), b = String(Math.round(root.scale_max));
        return a.length > b.length ? a : b;
    }
    TextMetrics { id: temp_24; font.family: Style.font_family; font.pixelSize: 24; text: root.widest_temp }
    TextMetrics { id: temp_32; font.family: Style.font_family; font.pixelSize: 32; text: root.widest_temp }

    // Pokémon-menu double border around the whole column, sized to the padding reserved above.
    PixelBox {
        visible: root.selected
        anchors.fill: parent
        fill: "transparent"
        rings: [Style.pixel_shades[3], "transparent", Style.pixel_shades[3]]
    }

    Column {
        x: Math.round((root.width - width) / 2)
        y: root.box_pad + Math.round((root.avail_h - height) / 2)
        spacing: root.fill_spacing

        Row {
            id: label_row
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            Text {
                visible: root.selected
                anchors.verticalCenter: parent.verticalCenter
                text: "▶"
                color: Style.pixel_shades[3]
                font.family: Style.font_family
                font.pixelSize: Style.font_size
            }

            Text {
                text: root.day ? (root.day_index === 0 ? "TODAY" : root.day.weekday.toUpperCase()) : ""
                color: root.selected ? Style.pixel_shades[3] : Style.pixel_shades[2]
                font.family: Style.font_family
                font.pixelSize: root.text_size
            }
        }

        Item {
            id: photo_box
            anchors.horizontalCenter: parent.horizontalCenter
            width: photo.width + 18
            height: photo.height + 18
            transform: Translate { y: root.hop_offset }

            PixelBox {
                anchors.fill: parent
                fill: Style.pixel_shades[3]
                rings: root.selected ? [Style.pixel_shades[0], Style.pixel_shades[3], Style.pixel_shades[0]] : ["transparent", Style.pixel_shades[2], Style.pixel_shades[0]]
            }

            PixelSprite {
                id: photo
                x: 9
                y: 9
                pixel: root.pixel
                rows: root.day ? PixelArt.photo(root.day.code, root.day_index) : []
            }
        }

        DotBar {
            id: dot_bar
            visible: root.sub === 0
            anchors.horizontalCenter: parent.horizontalCenter
            low: root.day ? root.day.min : 0
            high: root.day ? root.day.max : 0
            scale_min: root.scale_min
            scale_max: root.scale_max
            dot: root.pixel * 2
        }

        Column {
            id: temp_row
            visible: root.sub === 0
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            PixelTemp {
                anchors.horizontalCenter: parent.horizontalCenter
                value: root.day ? root.day.max : 0
                color: Style.pixel_shades[3]
                font_size: root.hi_size
            }

            PixelTemp {
                anchors.horizontalCenter: parent.horizontalCenter
                value: root.day ? root.day.min : 0
                color: Style.pixel_shades[2]
                font_size: root.text_size
            }
        }

        Text {
            id: pop_text
            visible: root.sub === 0
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.day ? root.day.pop + "%" : ""
            color: Style.pixel_shades[2]
            font.family: Style.font_family
            font.pixelSize: root.text_size
        }
        Column {
            id: stat_col
            visible: root.sub !== 0
            width: root.avail_w - 2
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.max(4, root.fill_spacing / 2)

            Repeater {
                model: root.stats

                Column {
                    id: stat
                    required property var modelData
                    width: stat_col.width
                    spacing: 2

                    Text {
                        text: stat.modelData.name
                        color: Style.pixel_shades[2]
                        font.family: Style.font_family
                        font.pixelSize: 8
                    }

                    Row {
                        spacing: 4

                        Text {
                            id: stat_value
                            text: stat.modelData.value
                            color: Style.pixel_shades[3]
                            font.family: Style.font_family
                            font.pixelSize: stat.modelData.small ? 16 : root.value_size
                        }

                        Text {
                            anchors.baseline: stat_value.baseline
                            text: stat.modelData.unit
                            color: Style.pixel_shades[2]
                            font.family: Style.font_family
                            font.pixelSize: 8
                        }
                    }

                    DexStatBar {
                        width: parent.width
                        value: stat.modelData.fill
                    }
                }
            }
        }

        Text {
            id: foot_text
            visible: root.sub !== 0 && root.foot !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.foot
            color: Style.pixel_shades[2]
            font.family: Style.font_family
            font.pixelSize: root.text_size
        }
    }
}
