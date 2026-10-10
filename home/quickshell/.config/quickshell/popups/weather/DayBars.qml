// home/quickshell/.config/quickshell/popups/weather/DayBars.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../services"

// Default day column: range band, wind, UV or sunshine bars by sub, then rain chance, icon and label.
ColumnLayout {
    id: root

    property var day: ({})
    property int day_index: 0
    property bool selected: false
    property int sub: 0
    property string label: ""
    property real col_w: 0
    property bool dq: false
    property bool mission: false
    property bool save_blocks: false
    property bool ladder: false
    property bool thin_range: false
    property int bar_area_h: 170
    property int icon_size: 64
    property real wind_max: 1
    property real top_y: 0
    property real bottom_y: 0

    anchors.margins: root.dq ? 8 : 2
    spacing: 2

    SaveBlock {
        visible: root.save_blocks
        Layout.alignment: Qt.AlignHCenter
        block_size: Math.max(24, Math.min(48, root.col_w - 8))
        day: root.day
        selected: root.selected
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
            color: Style.pal.blue
            opacity: 0.35
            height: (Math.max(0, Math.min(100, root.day.pop)) / 100) * parent.height
        }

        Rectangle {
            id: inner_band
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.thin_range ? 1 : parent.width * 0.3
            radius: Style.radius(2)
            color: root.ladder ? (root.selected ? (Style.selection_brackets.a > 0 ? Style.selection_brackets : Theme.theme_label) : Style.text_primary) : !Style.range_line ? Style.chart_fill : root.selected ? Style.text_accent : Style.text_strong
            border.width: Style.chart_outline.a > 0 && !root.ladder ? 1 : 0
            border.color: Style.chart_outline
            y: root.top_y
            height: Math.max(4, root.bottom_y - root.top_y)
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
            text: Math.round(root.day.max) + "°"
            color: root.thin_range ? Style.text_strong : Style.pal.yellow
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: inner_band.y + inner_band.height + (root.thin_range ? 5 : 1)
            text: Math.round(root.day.min) + "°"
            color: root.thin_range ? Style.text_muted : Style.pal.yellow
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
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
            rotation: root.day.wind_dir
            color: Style.pal.cyan
            font.pixelSize: Style.fs(-3)
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.5
            radius: Style.radius(2)
            color: Style.pal.cyan
            opacity: 0.5
            height: (root.day.wind_speed_max / root.wind_max) * (parent.height - 36)
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.6
            height: 2
            color: Style.pal.bright_cyan
            y: parent.height - (root.day.wind_gusts_max / root.wind_max) * (parent.height - 36)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(16, parent.height - (root.day.wind_gusts_max / root.wind_max) * (parent.height - 36) - 18)
            text: Math.round(root.day.wind_speed_max)
            color: Style.pal.cyan
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
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
            color: WeatherState.uv_color(root.day.uv_max)
            opacity: 0.7
            height: Math.min(1, root.day.uv_max / 12) * (parent.height - 18)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - Math.min(1, root.day.uv_max / 12) * (parent.height - 18) - 16
            text: root.day.uv_max.toFixed(1)
            color: WeatherState.uv_color(root.day.uv_max)
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
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
            color: Style.pal.yellow
            opacity: 0.55
            height: Math.min(1, root.day.sunshine_hours / 14) * (parent.height - 18)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - Math.min(1, root.day.sunshine_hours / 14) * (parent.height - 18) - 16
            text: root.day.sunshine_hours.toFixed(1) + "h"
            color: Style.pal.yellow
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }
    }

    Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.day.pop + "%"
        color: Style.pal.blue
        font.family: Style.font_family
        font.pixelSize: Style.fs(-2)
    }

    Item {
        id: icon_box
        visible: !root.save_blocks
        readonly property real size: Math.max(16, Math.min(root.icon_size, root.col_w - 4))
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
            source: WeatherState.icon_source(root.day.code, true)
            smooth: true
        }
    }

    Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        id: day_name
        text: root.label
        color: root.dq ? Style.pal.fg_strong : root.selected ? Style.pal.secondary : Style.pal.fg
        font.family: Style.font_family
        font.pixelSize: Style.fs(-2)

        Text {
            visible: root.dq && root.selected && Style.caret_phase
            anchors.right: parent.horizontalCenter
            anchors.rightMargin: day_name.contentWidth / 2 + 3
            anchors.verticalCenter: parent.verticalCenter
            text: Style.row_cursor
            color: Style.caret_color
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
        }
    }

    Text {
        visible: root.mission
        opacity: root.day_index === 0 ? 1 : 0
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "IN PROGRESS"
        color: Style.accent_color
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.letterSpacing: 1
    }
}
