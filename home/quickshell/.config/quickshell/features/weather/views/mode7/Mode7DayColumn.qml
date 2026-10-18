import QtQuick
import QtQuick.Effects
import qs.theme
import qs.services
import qs.styles.snes.widgets as Snes
import qs.features.weather
import qs.features.popups

// One day as a 16-bit gauge pillar standing on the Mode 7 floor, a plinth at its foot.
// Temp & Precip: lit from the day's low to its high, rain on the plinth. Wind, UV and Sunshine: lit from the floor up to the value.
Item {
    id: root

    property var day: null
    property int sub: 0
    // The week's strongest gust, shared by every column so wind pillars compare across days.
    property real wind_max: 1
    property int day_index: 0
    property string label: ""
    property bool selected: false
    property real col_w: 0
    // The week's coldest low and warmest high, shared by every column so ranges compare across days.
    property real scale_min: 0
    property real scale_max: 1

    // Silkscreen sits on an 8px grid, so narrow columns drop a whole grid step rather than blur at an odd size.
    readonly property int text_px: root.width >= 56 ? Style.font_size : Style.fs(-8)
    readonly property int small_px: Style.fs(-8)
    readonly property int icon_scale: Math.max(1, Math.min(3, Math.floor((root.width - 8) / 16)))

    readonly property real pillar_w: Math.round(Math.max(12, Math.min(28, root.width * 0.36)))
    readonly property real cap_h: Math.max(4, Math.round(root.pillar_w * 0.4))
    readonly property real plinth_h: root.small_px + 14
    readonly property real floor_y: root.height - root.plinth_h + 4
    // Room under the coldest low for its readout, and over the warmest high for the cursor and high readout.
    readonly property real lo_room: root.text_px + 6
    readonly property real scale_top_y: icon_box.y + icon_box.height + 14 + root.text_px + root.cap_h / 2
    readonly property real span_h: Math.max(10, root.floor_y - root.lo_room - root.scale_top_y)
    readonly property bool is_range: root.sub === 0
    readonly property real hi_y: Math.round(root.is_range ? root.temp_y(root.day ? root.day.max : root.scale_min) : root.level_y(root.level))
    readonly property real lo_y: root.is_range ? Math.max(root.hi_y + 2, Math.round(root.temp_y(root.day ? root.day.min : root.scale_min))) : root.floor_y
    // The pillar's empty track runs up to the scale top on single-value subs, so a short value reads as short.
    readonly property real track_top_y: root.is_range ? root.hi_y : Math.round(root.scale_top_y)
    readonly property real pop: root.day ? Math.max(0, Math.min(1, (root.day.pop || 0) / 100)) : 0

    // Wind against the week's strongest gust, UV against the top of the scale, sunshine against a 14 hour day.
    readonly property real level: {
        if (!root.day) return 0;
        const raw = [0, root.day.wind_speed_max / Math.max(1, root.wind_max), root.day.uv_max / 12, root.day.sunshine_hours / 14][root.sub];
        return Math.max(0, Math.min(1, raw));
    }
    readonly property real gust_level: root.day ? Math.max(0, Math.min(1, root.day.wind_gusts_max / Math.max(1, root.wind_max))) : 0
    // Share of the daylight that was sunny, for the sunshine plinth.
    readonly property real sunny_share: {
        const rise = root.day ? root.hm_minutes(root.day.sunrise) : -1;
        const set = root.day ? root.hm_minutes(root.day.sunset) : -1;
        if (rise < 0 || set <= rise) return 0;
        return Math.max(0, Math.min(1, root.day.sunshine_hours * 60 / (set - rise)));
    }
    readonly property color base_color: [Style.pal.primary_strong, Style.pal.cyan, root.day ? WeatherState.uv_color(root.day.uv_max) : Style.pal.green, Style.pal.yellow][root.sub]
    readonly property color gauge_fill: root.base_color
    readonly property color gauge_shade: root.is_range ? Qt.tint(Style.pal.primary_light, Qt.alpha(Style.pal.fg_strong, 0.3)) : Qt.tint(root.base_color, Qt.alpha(Style.pal.fg_strong, 0.4))

    readonly property string value_text: {
        if (!root.day) return "";
        return [Math.round(root.day.max) + "°", String(Math.round(root.day.wind_speed_max)), root.day.uv_max.toFixed(1), root.day.sunshine_hours.toFixed(1) + "h"][root.sub];
    }
    readonly property string plinth_text: {
        if (!root.day) return "";
        return [(root.day.pop || 0) + "%", String(Math.round(root.day.wind_gusts_max)), WeatherState.uv_band(root.day.uv_max).label.toUpperCase(), Math.round(root.sunny_share * 100) + "%"][root.sub];
    }
    readonly property real plinth_fill: [root.pop, root.gust_level, root.level, root.sunny_share][root.sub]
    // Darkened so the plinth's white readout stays legible over a yellow or cyan fill.
    readonly property color plinth_color: root.is_range ? Style.pal.info : Qt.darker(root.base_color, 2)

    // Stepped, not eased: SNES menu cursors jump whole pixels.
    property int bob: 0

    function hm_minutes(hm) {
        const parts = (hm || "").split(":");
        return parts.length === 2 ? parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10) : -1;
    }

    function level_y(frac) {
        return root.floor_y - Math.max(0.03, frac) * (root.floor_y - root.scale_top_y);
    }

    function temp_y(temp) {
        const frac = Math.max(0, Math.min(1, (temp - root.scale_min) / Math.max(0.01, root.scale_max - root.scale_min)));
        return root.floor_y - root.lo_room - frac * root.span_h;
    }

    SequentialAnimation {
        running: root.selected && Popups.open_name === "weather"
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.bob = 0
        PropertyAction { target: root; property: "bob"; value: 0 }
        PauseAnimation { duration: 180 }
        PropertyAction { target: root; property: "bob"; value: 2 }
        PauseAnimation { duration: 180 }
        PropertyAction { target: root; property: "bob"; value: 3 }
        PauseAnimation { duration: 180 }
        PropertyAction { target: root; property: "bob"; value: 2 }
        PauseAnimation { duration: 180 }
    }

    Text {
        id: label_text
        y: 2
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.label.toUpperCase()
        color: root.selected ? Style.pal.fg_strong : Style.pal.primary_light
        font.family: Style.font_family
        font.pixelSize: root.text_px
        style: Text.Raised
        styleColor: Style.text_shadow
    }

    // The icon's art crop is rasterised at 16px and blown up unsmoothed, so it reads as a 16x16 sprite.
    Item {
        id: icon_box
        readonly property var crop: root.day ? WeatherState.icon_crop(root.day.code, true) : [0, 0, 128]
        readonly property real unit: 16 / icon_box.crop[2]
        x: Math.round((root.width - width) / 2)
        y: label_text.y + label_text.height + 4
        width: 16 * root.icon_scale
        height: width
        clip: true
        visible: false

        Image {
            x: -Math.round(icon_box.crop[0] * icon_box.unit) * root.icon_scale
            y: -Math.round(icon_box.crop[1] * icon_box.unit) * root.icon_scale
            width: Math.round(128 * icon_box.unit) * root.icon_scale
            height: width
            sourceSize.width: Math.round(128 * icon_box.unit)
            sourceSize.height: Math.round(128 * icon_box.unit)
            source: root.day ? WeatherState.icon_source(root.day.code, true) : ""
            smooth: false
            mipmap: false
        }
    }

    // Unblurred shadow one sprite pixel down-right, the 16-bit stand-in for an outline.
    MultiEffect {
        source: icon_box
        x: icon_box.x
        y: icon_box.y
        width: icon_box.width
        height: icon_box.height
        shadowEnabled: true
        shadowBlur: 0
        shadowHorizontalOffset: root.icon_scale
        shadowVerticalOffset: root.icon_scale
        shadowColor: Style.pal.bg_shadow
        shadowOpacity: 0.9
    }

    // Above the pillar's empty track, which on single-value subs reaches past the value.
    Column {
        z: 1
        visible: root.selected
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.hi_y - root.cap_h / 2 - root.text_px - 13 + root.bob

        Repeater {
            model: [10, 6, 2]

            Rectangle {
                required property var modelData
                anchors.horizontalCenter: parent.horizontalCenter
                width: modelData
                height: 2
                color: Style.pal.fg_strong
            }
        }
    }

    Text {
        z: 1
        width: root.width
        y: root.hi_y - root.cap_h / 2 - root.text_px - 3
        horizontalAlignment: Text.AlignHCenter
        text: root.value_text
        color: Style.pal.fg_strong
        font.family: Style.font_family
        font.pixelSize: root.text_px
        style: Text.Raised
        styleColor: Style.text_shadow
    }

    Item {
        x: Math.round((root.width - root.pillar_w) / 2)
        y: root.track_top_y
        width: root.pillar_w
        height: root.floor_y - root.track_top_y + 2

        Rectangle {
            visible: root.selected
            anchors.fill: parent
            anchors.margins: -3
            anchors.topMargin: -root.cap_h / 2 - 3
            radius: 4
            color: Qt.alpha(Style.pal.secondary, 0.3)
        }

        // Empty gauge track below the day's low.
        Rectangle {
            anchors.fill: parent
            color: Qt.tint(Style.pal.bg_crust, Qt.alpha(Style.pal.primary_strong, 0.3))
            border.width: 1
            border.color: Style.pal.fg_muted
        }

        // The SnesGauge fill stood upright, deep blue at the low lightening toward the high, notched every 8px.
        Rectangle {
            id: range_fill
            x: 1
            y: root.hi_y - root.track_top_y
            width: parent.width - 2
            height: root.lo_y - root.hi_y
            gradient: Gradient {
                GradientStop { position: 0; color: root.gauge_shade }
                GradientStop { position: 1; color: root.gauge_fill }
            }

            Repeater {
                model: Math.floor(range_fill.height / 8)

                Rectangle {
                    required property int index
                    y: range_fill.height - index * 8 - 8
                    width: range_fill.width
                    height: 1
                    color: Qt.alpha(Style.pal.bg_crust, 0.35)
                }
            }
        }

        // Hard-edged cylinder shading: a glint on the lit face, then a shaded side.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.12; color: "transparent" }
                GradientStop { position: 0.13; color: Qt.alpha(Style.pal.fg_strong, 0.28) }
                GradientStop { position: 0.24; color: Qt.alpha(Style.pal.fg_strong, 0.28) }
                GradientStop { position: 0.25; color: "transparent" }
                GradientStop { position: 0.62; color: "transparent" }
                GradientStop { position: 0.63; color: Qt.alpha(Style.pal.bg_shadow, 0.35) }
                GradientStop { position: 1; color: Qt.alpha(Style.pal.bg_shadow, 0.5) }
            }
        }

        Rectangle {
            y: root.hi_y - root.track_top_y - root.cap_h / 2
            width: parent.width
            height: root.cap_h
            radius: height / 2
            border.width: 1
            border.color: root.selected ? Style.pal.fg_strong : Style.pal.fg_muted
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: root.selected ? Style.pal.fg_strong : Style.pal.primary_light }
                GradientStop { position: 0.62; color: root.selected ? Qt.tint(Style.pal.fg_strong, Qt.alpha(Style.pal.secondary, 0.5)) : Style.pal.primary_light }
                GradientStop { position: 0.63; color: root.selected ? Style.pal.secondary : Style.pal.primary }
                GradientStop { position: 1; color: root.selected ? Style.pal.secondary : Style.pal.primary }
            }
        }
    }

    // The day's strongest gust, as a notch across the pillar at that level.
    Rectangle {
        visible: root.sub === 1 && root.gust_level > root.level
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(root.level_y(root.gust_level))
        width: root.pillar_w + 8
        height: 2
        color: Style.pal.fg_strong
    }

    Text {
        visible: root.is_range
        width: root.width
        y: root.lo_y + 2
        horizontalAlignment: Text.AlignHCenter
        text: root.day ? Math.round(root.day.min) + "°" : ""
        color: Style.pal.primary_light
        font.family: Style.font_family
        font.pixelSize: root.text_px
        style: Text.Raised
        styleColor: Style.text_shadow
    }

    // The plinth doubles as a water tank, filled left to right to the rain chance.
    Snes.SnesWindow {
        id: plinth
        x: Math.round((root.width - width) / 2)
        y: root.floor_y
        width: Math.min(root.width, Math.max(root.pillar_w + 12, plinth_label.implicitWidth + 12 + (wind_arrow.visible ? wind_arrow.width + 2 : 0)))
        height: root.plinth_h - 4
        radius: 3
        drop: 2
        lit: root.selected

        Rectangle {
            x: 3
            y: 3
            width: Math.max(0, plinth.panel.width - 6) * root.plinth_fill
            height: plinth.panel.height - 6
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.tint(root.plinth_color, Qt.alpha(Style.pal.fg_strong, 0.35)) }
                GradientStop { position: 1; color: root.plinth_color }
            }
        }

        Text {
            id: wind_arrow
            visible: root.sub === 1
            x: 5
            anchors.verticalCenter: plinth.panel.verticalCenter
            text: "▲"
            rotation: root.day ? root.day.wind_dir : 0
            color: Style.pal.fg_strong
            font.pixelSize: root.small_px
        }

        Text {
            id: plinth_label
            anchors.centerIn: plinth.panel
            anchors.horizontalCenterOffset: wind_arrow.visible ? wind_arrow.width / 2 + 1 : 0
            text: root.plinth_text
            color: Style.pal.fg_strong
            font.family: Style.font_family
            font.pixelSize: root.small_px
            style: Text.Raised
            styleColor: Style.text_shadow
        }
    }
}
