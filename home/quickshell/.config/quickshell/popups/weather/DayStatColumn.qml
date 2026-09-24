// home/quickshell/.config/quickshell/popups/weather/DayStatColumn.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../../theme"
import "../../services"

// One day as a stat column: a header tab, a segmented range bar on the week's scale, the icon, high, change against today, low and rain chance.
Item {
    id: root

    property var day: null
    property int day_index: 0
    property bool selected: false
    // The shared scale the range bar is cut from.
    property real scale_min: 0
    property real scale_max: 1
    readonly property int segments: Math.max(12, Math.floor((root.height - 40) / 7))
    readonly property real seg_span: (root.scale_max - root.scale_min) / root.segments
    readonly property int change: root.day && WeatherState.days.length > 0 ? Math.round(root.day.max) - Math.round(WeatherState.days[0].max) : 0

    CutBox {
        anchors.fill: parent
        cut_tr: 8
        fill: Style.row_rule
        fill_end: Style.row_rule
        stroke: root.selected ? Style.selection_rule : Style.row_rule
    }

    CornerTick {
        color: root.selected ? Style.selection_rule : Style.corner_tick
    }

    Rectangle {
        id: head
        width: parent.width - 8
        height: head_row.implicitHeight + 6
        color: root.selected ? Qt.alpha(Style.caret_color, 0.2) : Qt.alpha(Theme.theme_primary_strong, 0.26)

        Rectangle {
            visible: root.selected
            anchors.bottom: parent.bottom
            width: parent.width
            height: 2
            color: Style.caret_color
        }

        RowLayout {
            id: head_row
            anchors.fill: parent
            anchors.leftMargin: 5
            anchors.rightMargin: 2
            spacing: 2

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.day ? root.day.weekday : ""
                color: root.selected ? Style.text_strong : Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.font_size - 3
                font.bold: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
            }

            Text {
                visible: root.width > 60
                text: "D" + (root.day_index + 1)
                color: Style.text_muted
                font.family: Style.mono_font
                font.pixelSize: Style.font_size - 6
            }
        }
    }

    SegBar {
        id: range_bar
        x: 6
        anchors.top: head.bottom
        anchors.topMargin: 6
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        width: 7
        vertical: true
        count: root.segments
        first_lit: root.day ? Math.floor((root.day.min - root.scale_min) / root.seg_span) : 0
        last_lit: root.day ? Math.ceil((root.day.max - root.scale_min) / root.seg_span) - 1 : -1
        on_color: root.selected ? Style.caret_color : Style.meter_on
        off_color: Style.meter_off
    }

    ColumnLayout {
        anchors.left: range_bar.right
        anchors.leftMargin: 7
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.top: head.bottom
        anchors.topMargin: 6
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        spacing: 2

        Image {
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22
            readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
            sourceSize.width: Math.ceil(44 * dpr)
            sourceSize.height: Math.ceil(44 * dpr)
            source: root.day ? WeatherState.icon_source(root.day.code, true) : ""
            smooth: true
        }

        Item {
            Layout.fillHeight: true
        }

        Row {
            spacing: 1

            Text {
                id: hi_text
                text: root.day ? Math.round(root.day.max) : ""
                color: Style.text_strong
                font.family: Style.number_font
                font.pixelSize: Style.font_size + 5
            }

            Text {
                text: "°"
                color: Style.text_muted
                font.family: Style.mono_font
                font.pixelSize: Style.font_size - 3
            }
        }

        Text {
            text: root.day_index === 0 ? "REF" : root.change > 0 ? "▲" + root.change : root.change < 0 ? "▼" + (-root.change) : "="
            color: root.day_index === 0 || root.change === 0 ? Style.text_muted : root.change > 0 ? Theme.ok : Theme.theme_label
            font.family: Style.mono_font
            font.pixelSize: Style.font_size - 4
        }

        Text {
            text: root.day ? Math.round(root.day.min) + "°" : ""
            color: Style.text_muted
            font.family: Style.mono_font
            font.pixelSize: Style.font_size - 3
        }

        Text {
            text: root.day ? root.day.pop + "%" : ""
            color: Theme.info
            font.family: Style.mono_font
            font.pixelSize: Style.font_size - 5
        }
    }
}
