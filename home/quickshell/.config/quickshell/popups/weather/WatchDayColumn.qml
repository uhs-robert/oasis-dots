// home/quickshell/.config/quickshell/popups/weather/WatchDayColumn.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components/goldeneye" as Goldeneye
import "../../lock/skins/goldeneye" as Watch
import "../../theme/Watch.js" as W

// One Daily column as a strip of the pause watch's bezel: warm segments lit from the day's low to its high on the week's scale,
// a thin cold strip beside it lit to the rain chance, readings in the LCD digits; the selected day sits in a watch-face panel.
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

    readonly property real span: Math.max(1, root.scale_max - root.scale_min)
    readonly property real lit_alpha: root.selected ? 1 : 0.6
    readonly property real unlit_alpha: root.selected ? 0.2 : 0.14
    readonly property color text_color: root.selected ? Style.wk.lit : Style.wk.mid
    readonly property real seg_h: 6
    readonly property real seg_gap: 3
    readonly property real warm_w: Math.max(8, Math.min(18, root.width * 0.22))
    readonly property real cold_w: Math.max(4, Math.round(root.warm_w * 0.4))
    // Every column has the same height, so the count matches across days and the segments line up into week-wide temperature bands.
    readonly property int seg_count: Math.max(6, Math.min(24, Math.floor((strips.height + root.seg_gap) / (root.seg_h + root.seg_gap))))
    readonly property int rain_lit: root.day ? Math.round(root.day.pop / 100 * root.seg_count) : 0

    // Inclusive overlap, so a day whose low equals its high still lights the segment holding it.
    function temp_lit(from_bottom) {
        if (!root.day) return false;
        const lo = root.scale_min + from_bottom * root.span / root.seg_count;
        const hi = lo + root.span / root.seg_count;
        return hi >= root.day.min && lo <= root.day.max;
    }

    onSelectedChanged: if (root.selected) burst.play()

    Watch.PanelShape {
        visible: root.selected
        anchors.fill: parent
        cut: 8
        notch_w: 4
        notch_h: 16
        top_color: Style.wk.panel_top
        bottom_color: Style.wk.panel_bottom
        edge: Style.wk.edge
    }

    Rectangle {
        visible: root.selected
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 20
        height: 2
        color: Style.caret_color
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        spacing: 4

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.label
            color: root.text_color
            font.family: W.head_font
            font.pixelSize: Style.fs(-5)
            font.letterSpacing: 1
            font.capitalization: Font.AllUppercase
        }

        WeatherIcon {
            Layout.alignment: Qt.AlignHCenter
            size: Math.max(18, Math.min(32, root.width - 16))
            code: root.day ? root.day.code : 0
            tint: root.text_color
            opacity: root.selected ? 1 : 0.8
        }

        DigitText {
            text: root.day ? String(Math.round(root.day.max)) : "--"
        }

        Item {
            id: strips
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 6 * (root.seg_h + root.seg_gap)

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                spacing: 4

                SegmentColumn {
                    seg_w: root.warm_w
                    // Yellow at the cold end to red at the hot end, as the watch's warm bezel runs.
                    color_of: from_bottom => W.warm[7 - Math.round(from_bottom * 7 / Math.max(1, root.seg_count - 1))]
                    lit_of: from_bottom => root.temp_lit(from_bottom)
                }

                SegmentColumn {
                    visible: root.width >= 40
                    seg_w: root.cold_w
                    color_of: from_bottom => W.cold_lit[Math.round(from_bottom * 7 / Math.max(1, root.seg_count - 1))]
                    lit_of: from_bottom => from_bottom < root.rain_lit
                }
            }
        }

        DigitText {
            text: root.day ? String(Math.round(root.day.min)) : "--"
            opacity: 0.8
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.day ? root.day.pop + "%" : ""
            color: W.cold_lit[7]
            opacity: root.selected ? 1 : 0.8
            font.family: W.mono_font
            font.pixelSize: Style.fs(-3)
        }
    }

    Goldeneye.StaticBurst {
        id: burst
        anchors.fill: parent
    }

    component DigitText: Text {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: root.width - 8
        elide: Text.ElideRight
        color: root.text_color
        font.family: W.digit_font
        font.pixelSize: Style.fs(0)
    }

    // A vertical run of slanted bezel segments; `color_of` and `lit_of` take a segment's place counted from the bottom.
    component SegmentColumn: Column {
        id: segment_column
        property real seg_w: 10
        property var color_of: from_bottom => "transparent"
        property var lit_of: from_bottom => false
        spacing: root.seg_gap

        Repeater {
            model: root.seg_count

            Rectangle {
                required property int index
                readonly property int from_bottom: root.seg_count - 1 - index
                width: segment_column.seg_w
                height: root.seg_h
                color: segment_column.color_of(from_bottom)
                opacity: segment_column.lit_of(from_bottom) ? root.lit_alpha : root.unlit_alpha
                antialiasing: true
                transform: Matrix4x4 {
                    matrix: Qt.matrix4x4(1, -Style.chart_slant, 0, Style.chart_slant * root.seg_h, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                }
            }
        }
    }
}
