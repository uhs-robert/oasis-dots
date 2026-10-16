import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services

// One day as a PS2 boot-screen tower. Temp: a translucent prism as tall as the day's high, filled with water to its rain chance.
// Wind: as tall as the gusts, filled to the speed. UV and sunshine: filled prisms as tall as the value.
Item {
    id: root

    property var day: ({})
    property bool selected: false
    property real scale_min: 0
    property real scale_max: 1
    property real labels_h: 60
    property int sub: 0
    property real wind_max: 1

    readonly property real area_h: Math.max(20, root.height - root.labels_h)
    readonly property real sub_frac: root.sub === 1 ? Math.min(1, (root.day.wind_gusts_max || 0) / Math.max(1, root.wind_max))
        : root.sub === 2 ? Math.min(1, (root.day.uv_max || 0) / 12)
        : root.sub === 3 ? Math.min(1, (root.day.sunshine_hours || 0) / 14)
        : root.frac(root.day.max || 0)
    readonly property real tower_h: root.area_h * (0.12 + 0.78 * root.sub_frac)
    readonly property real lo_y: root.area_h * (0.12 + 0.78 * root.frac(root.day.min || 0))
    readonly property real tower_w: Math.max(14, Math.min(34, root.width * 0.46))
    readonly property real pop: Math.max(0, Math.min(1, (root.day.pop || 0) / 100))
    readonly property color hi_color: WeatherState.temp_color(root.day.max || 0)
    readonly property color lo_color: WeatherState.temp_color(root.day.min || 0)
    readonly property color rain_color: root.pop > 0 ? Theme.info : Style.text_muted
    readonly property color uv_color: WeatherState.uv_color(root.day.uv_max || 0)
    // Fill height as a share of the tower, and the fill and cap colours, per sub.
    readonly property real fill_share: root.sub === 1 ? Math.min(1, (root.day.wind_speed_max || 0) / Math.max(1, root.day.wind_gusts_max || 1))
        : root.sub === 0 ? root.pop : 1
    readonly property color fill_color: [Theme.info, Style.pal.cyan, root.uv_color, Style.pal.yellow][root.sub]
    readonly property color cap_color: [root.hi_color, Style.pal.bright_cyan, root.uv_color, Style.pal.yellow][root.sub]
    readonly property string day_length_share: {
        const rise = root.hm_minutes(root.day.sunrise);
        const set = root.hm_minutes(root.day.sunset);
        if (rise === null || set === null || set <= rise) return "";
        return Math.round((root.day.sunshine_hours || 0) * 60 / (set - rise) * 100) + "% of day";
    }

    function hm_minutes(hm) {
        const parts = (hm || "").split(":");
        return parts.length === 2 ? parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10) : null;
    }

    function frac(v) {
        return Math.max(0, Math.min(1, (v - root.scale_min) / Math.max(0.01, root.scale_max - root.scale_min)));
    }

    Item {
        id: tower
        x: (root.width - root.tower_w) / 2
        y: root.area_h - root.tower_h
        width: root.tower_w
        height: root.tower_h
        opacity: root.selected ? 1 : 0.55

        Behavior on opacity {
            NumberAnimation {
                duration: 160
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -5
            anchors.bottomMargin: 0
            radius: 6
            color: Qt.alpha(Theme.theme_primary, root.selected ? 0.24 : 0.08)
        }

        Rectangle {
            anchors.fill: parent
            radius: 2
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary_light, 0.7) }
                GradientStop { position: 0.3; color: Qt.alpha(Theme.theme_primary_strong, 0.55) }
                GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary_strong, 0.2) }
            }
        }

        Rectangle {
            anchors.right: parent.right
            width: parent.width * 0.38
            height: parent.height
            radius: 2
            color: Qt.alpha(Theme.bg_shadow, 0.28)
        }

        Rectangle {
            width: parent.width
            height: 2
            radius: 1
            color: Qt.alpha(root.cap_color, root.selected ? 0.95 : 0.6)
        }

        Rectangle {
            anchors.bottom: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width + 6
            height: 10
            radius: 5
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary_light, root.selected ? 0.35 : 0.15) }
            }
        }

        Rectangle {
            visible: root.sub === 0
            y: Math.min(parent.height - 1, root.lo_y > 0 ? root.tower_h - root.lo_y : parent.height - 1)
            x: 2
            width: parent.width - 4
            height: 1
            color: Qt.alpha(root.lo_color, 0.7)
        }

        Rectangle {
            anchors.top: parent.bottom
            width: parent.width
            height: Math.min(18, parent.height * 0.3)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary_strong, 0.3) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }

    Text {
        visible: root.sub === 1
        x: tower.x + (root.tower_w - width) / 2
        y: tower.y - height - 8
        text: "▲"
        rotation: root.day.wind_dir || 0
        color: Style.pal.cyan
        opacity: root.selected ? 1 : 0.7
        font.pixelSize: Style.fs(-3)
    }

    Item {
        visible: root.fill_share > 0
        x: tower.x + 1
        width: root.tower_w - 2
        height: Math.max(2, root.tower_h * root.fill_share)
        y: root.area_h - height
        opacity: root.selected ? 1 : 0.8

        Rectangle {
            anchors.fill: parent
            radius: 1
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(root.fill_color, 0.95) }
                GradientStop { position: 1; color: Qt.alpha(root.fill_color, root.sub === 0 ? 0.55 : 0.4) }
            }
        }

        Rectangle {
            anchors.right: parent.right
            width: parent.width * 0.38
            height: parent.height
            color: Qt.alpha(Theme.bg_shadow, 0.22)
        }

        Rectangle {
            width: parent.width
            height: 2
            color: Qt.lighter(root.fill_color, 1.35)
        }
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.labels_h
        spacing: 0

        Item {
            Layout.fillHeight: true
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.day.weekday || ""
            color: root.selected ? Theme.fg_strong : Theme.theme_primary_light
            font.family: Style.font_family
            font.pixelSize: Style.fs(-2)
            font.weight: root.selected ? Font.Medium : Font.Light
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: {
                const d = root.day;
                if (root.sub === 1) return d.wind_speed_max !== undefined ? Math.round(d.wind_speed_max) + " " + WeatherState.wind_unit() : "";
                if (root.sub === 2) return d.uv_max !== undefined ? d.uv_max.toFixed(1) : "";
                if (root.sub === 3) return d.sunshine_hours !== undefined ? d.sunshine_hours.toFixed(1) + "h" : "";
                return d.max !== undefined ? "<font color=\"" + root.hi_color + "\">" + Math.round(d.max) + "°</font> <font color=\"" + root.lo_color + "\">" + Math.round(d.min) + "°</font>" : "";
            }
            color: root.fill_color
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }

        Row {
            visible: root.sub === 0
            Layout.alignment: Qt.AlignHCenter
            spacing: 2

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f058c}"
                color: root.rain_color
                font.family: "Symbols Nerd Font"
                font.pixelSize: Style.fs(-4)
            }

            Text {
                text: (root.day.pop || 0) + "%"
                color: root.rain_color
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
            }
        }

        Text {
            visible: root.sub !== 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: {
                const d = root.day;
                if (root.sub === 1) return d.wind_gusts_max !== undefined ? "g" + Math.round(d.wind_gusts_max) + " " + WeatherState.wind_dir_label(d.wind_dir) : "";
                if (root.sub === 2) return d.uv_max !== undefined ? WeatherState.uv_band(d.uv_max).label : "";
                return root.day_length_share;
            }
            color: Theme.theme_primary_light
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
        }
    }
}
