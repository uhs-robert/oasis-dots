// home/quickshell/.config/quickshell/components/modern/DayColumn.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../services"

// One Daily column: day pill, icon, headline value, a vertical track, a second value and a footer; raised when selected.
// sub 0 is the temperature range on the week scale with rain chance, 1 wind speed with a gust cap and direction arrow,
// 2 the UV index in its band colour, 3 sunshine hours as a fill.
Item {
    id: root

    property var day: null
    property string label: ""
    property bool selected: false
    property real scale_min: 0
    property real scale_max: 1
    property int sub: 0
    property real wind_max: 1

    readonly property real span: Math.max(1, root.scale_max - root.scale_min)
    readonly property real wind_scale: Math.max(1, root.wind_max)
    readonly property real sun_scale: 14
    readonly property real uv_scale: 12

    // Daylight length of the day, the sunshine fill's own scale.
    readonly property string day_light: {
        const rise = root.day ? /^(\d+):(\d+)$/.exec(root.day.sunrise || "") : null;
        const set = root.day ? /^(\d+):(\d+)$/.exec(root.day.sunset || "") : null;
        if (!rise || !set) return "14h";
        const mins = (Number(set[1]) * 60 + Number(set[2])) - (Number(rise[1]) * 60 + Number(rise[2]));
        return (mins / 60).toFixed(1) + "h";
    }
    readonly property color uv_color: root.day ? WeatherState.uv_color(root.day.uv_max) : Theme.theme_primary
    // Fill height as a fraction of the track for the Wind, UV and Sunshine subs.
    readonly property real fill_fraction: {
        if (!root.day) return 0;
        if (root.sub === 1) return root.day.wind_speed_max / root.wind_scale;
        if (root.sub === 2) return root.day.uv_max / root.uv_scale;
        return root.day.sunshine_hours / root.sun_scale;
    }
    readonly property color fill_top: root.sub === 2 ? Qt.tint(root.uv_color, Qt.alpha(Theme.fg_strong, 0.25)) : root.sub === 3 ? "#ffd479" : Qt.tint(Theme.theme_primary_light, Qt.alpha(Theme.theme_secondary, 0.75))
    readonly property color fill_bottom: root.sub === 2 ? root.uv_color : root.sub === 3 ? "#f0a23c" : Theme.theme_primary
    readonly property string headline: {
        if (!root.day) return "";
        if (root.sub === 0) return Math.round(root.day.max) + "°";
        if (root.sub === 1) return String(Math.round(root.day.wind_speed_max));
        if (root.sub === 2) return root.day.uv_max.toFixed(1);
        return root.day.sunshine_hours.toFixed(1) + "h";
    }
    readonly property string second_line: {
        if (!root.day) return "";
        if (root.sub === 0) return Math.round(root.day.min) + "°";
        if (root.sub === 1) return "gust " + Math.round(root.day.wind_gusts_max);
        if (root.sub === 2) return WeatherState.uv_band(root.day.uv_max).label;
        return "sun";
    }

    CardSurface {
        visible: root.selected
        anchors.fill: parent
        selected: true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 8
        anchors.bottomMargin: 10
        spacing: 6

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Math.min(root.width - 4, day_text.implicitWidth + 14)
            implicitHeight: day_text.implicitHeight + 4
            radius: height / 2
            color: "transparent"
            gradient: root.selected ? pill_gradient : null

            Gradient {
                id: pill_gradient
                GradientStop { position: 0; color: Style.selection_shade.a > 0 ? Style.selection_shade : Style.selection_bg }
                GradientStop { position: 1; color: Style.selection_bg }
            }

            Text {
                id: day_text
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 4)
                elide: Text.ElideRight
                text: root.label
                color: root.selected ? Style.selection_fg : Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
                font.weight: Font.DemiBold
            }
        }

        // The icon art fills about half its box, so the box runs large and gives back its empty margin.
        Image {
            readonly property real size: Math.max(24, Math.min(48, root.width - 6))
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: size
            Layout.preferredHeight: size
            Layout.topMargin: -Math.round(size * 0.18)
            Layout.bottomMargin: -Math.round(size * 0.18)
            readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
            sourceSize.width: Math.ceil(96 * dpr)
            sourceSize.height: Math.ceil(96 * dpr)
            source: root.day ? WeatherState.icon_source(root.day.code, true) : ""
            smooth: true
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.headline
            color: root.sub === 2 ? root.uv_color : Style.text_strong
            font.family: Style.font_family
            font.pixelSize: Style.fs(1)
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            Layout.minimumHeight: 48
            Layout.maximumHeight: 150
            implicitWidth: 6

            Rectangle {
                id: track
                anchors.fill: parent
                radius: 3
                color: Qt.alpha(Theme.fg_core, 0.08)
            }

            Rectangle {
                visible: root.sub === 0
                readonly property real top_f: root.day ? (root.scale_max - root.day.max) / root.span : 0
                readonly property real bottom_f: root.day ? (root.scale_max - root.day.min) / root.span : 1
                width: track.width
                y: track.height * top_f
                height: Math.max(width, track.height * (bottom_f - top_f))
                radius: 3
                opacity: root.selected ? 1 : 0.7
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.tint(Theme.theme_primary_light, Qt.alpha(Theme.theme_secondary, 0.75)) }
                    GradientStop { position: 1; color: Theme.theme_primary }
                }
            }

            Rectangle {
                visible: root.sub !== 0
                width: track.width
                anchors.bottom: parent.bottom
                height: Math.max(width, track.height * Math.min(1, root.fill_fraction))
                radius: 3
                opacity: root.selected ? 1 : 0.75
                gradient: Gradient {
                    GradientStop { position: 0; color: root.fill_top }
                    GradientStop { position: 1; color: root.fill_bottom }
                }
            }

            Rectangle {
                visible: root.sub === 1 && !!root.day
                readonly property real gust_f: root.day ? Math.min(1, root.day.wind_gusts_max / root.wind_scale) : 0
                x: -3
                width: track.width + 6
                height: 3
                radius: 1.5
                y: Math.max(0, track.height * (1 - gust_f) - 1.5)
                color: Theme.theme_secondary
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.width - 4
            elide: Text.ElideRight
            text: root.second_line
            color: root.selected ? Style.text_dim : Style.text_muted
            font.family: Style.font_family
            font.pixelSize: root.sub === 0 ? Style.fs(-1) : Style.fs(-3)
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }

        Text {
            visible: root.sub === 0
            Layout.alignment: Qt.AlignHCenter
            text: root.day ? "\u{f058c} " + root.day.pop + "%" : ""
            color: Qt.tint(Style.text_dim, Qt.alpha(Theme.info, 0.7))
            font.family: Style.mono_font
            font.pixelSize: Style.fs(-4)
        }

        Row {
            visible: root.sub === 1
            Layout.alignment: Qt.AlignHCenter
            spacing: 3

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "▲"
                rotation: root.day ? root.day.wind_dir : 0
                color: Theme.theme_primary
                font.pixelSize: Style.fs(-3)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.day ? WeatherState.compass_label(root.day.wind_dir) : ""
                color: Qt.tint(Style.text_dim, Qt.alpha(Theme.theme_primary, 0.5))
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-4)
            }
        }

        Text {
            visible: root.sub === 2 || root.sub === 3
            Layout.alignment: Qt.AlignHCenter
            text: root.sub === 2 ? "UV" : "of " + root.day_light
            color: Style.text_muted
            font.family: Style.mono_font
            font.pixelSize: Style.fs(-4)
        }
    }
}
