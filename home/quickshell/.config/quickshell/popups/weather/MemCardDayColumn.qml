// home/quickshell/.config/quickshell/popups/weather/MemCardDayColumn.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// One day as a memory card save: its save block on top, the temperature range as a stack of save blocks on the
// week's scale, and the rain chance as a five-block readout. The selected day is framed like the selected save.
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

    readonly property bool has_day: !!root.day
    readonly property real temp_lo: root.has_day ? root.day.min : 0
    readonly property real temp_hi: root.has_day ? root.day.max : 0
    readonly property int pop: root.has_day ? Math.max(0, Math.min(100, root.day.pop || 0)) : 0
    readonly property int rain_blocks: 5
    readonly property int rain_used: Math.ceil(root.pop * root.rain_blocks / 100)

    function scale_pos(v) {
        return (v - root.scale_min) / Math.max(0.01, root.scale_max - root.scale_min);
    }

    Rectangle {
        visible: root.selected
        anchors.fill: frame
        anchors.margins: -2
        radius: frame.radius + 2
        color: "transparent"
        border.width: 2
        border.color: Qt.alpha(Theme.theme_primary_light, 0.3)
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        anchors.margins: 2
        radius: 4
        color: root.selected ? Qt.alpha(Style.selection_bg, 0.55) : "transparent"
        border.width: root.selected ? 2 : 1
        border.color: root.selected ? Theme.theme_primary_light : Qt.alpha(Style.frame_border_color, 0.35)
    }

    ColumnLayout {
        anchors.fill: frame
        anchors.margins: 4
        spacing: 2

        SaveBlock {
            Layout.alignment: Qt.AlignHCenter
            block_size: Math.max(20, Math.min(44, root.col_w - 16))
            day: root.has_day ? root.day : ({})
            selected: root.selected
        }

        Item {
            id: range_area
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property real text_h: hi_text.implicitHeight + 1

            SaveStack {
                id: range_stack
                anchors.horizontalCenter: parent.horizontalCenter
                y: range_area.text_h
                width: Math.max(8, Math.min(26, root.col_w * 0.38))
                height: Math.max(30, range_area.height - range_area.text_h * 2)
                low: root.scale_pos(root.temp_lo)
                high: root.scale_pos(root.temp_hi)
                scale_min: root.scale_min
                scale_max: root.scale_max
                selected: root.selected
            }

            Text {
                id: hi_text
                anchors.horizontalCenter: parent.horizontalCenter
                y: range_stack.y + range_stack.high_y - implicitHeight - 1
                text: root.has_day ? Math.round(root.temp_hi) + "°" : ""
                color: root.selected ? Style.text_strong : WeatherState.temp_color(root.temp_hi)
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
                style: Text.Raised
                styleColor: Style.text_shadow
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: range_stack.y + range_stack.low_bottom + 1
                text: root.has_day ? Math.round(root.temp_lo) + "°" : ""
                color: WeatherState.temp_color(root.temp_lo)
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
            }
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 2
            spacing: 2

            Repeater {
                model: root.rain_blocks

                Rectangle {
                    id: rain_block
                    required property int index
                    readonly property bool is_used: rain_block.index < root.rain_used

                    width: Math.max(3, Math.min(8, (root.col_w - 20) / root.rain_blocks - 2))
                    height: 6
                    radius: 1
                    color: rain_block.is_used ? Qt.alpha(Theme.info, root.selected ? 1 : 0.75) : Qt.alpha(Theme.bg_shadow, 0.45)
                    border.width: 1
                    border.color: rain_block.is_used ? Qt.lighter(Theme.info, 1.3) : Qt.alpha(Style.frame_border_color, 0.6)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.pop + "%"
            color: root.pop > 0 ? Theme.info : Style.text_muted
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.label.toUpperCase()
            color: root.selected ? Theme.theme_primary_light : Style.text_fg
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
            style: root.selected ? Text.Raised : Text.Normal
            styleColor: Style.text_shadow
        }
    }
}
