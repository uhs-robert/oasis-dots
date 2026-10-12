// home/quickshell/.config/quickshell/popups/weather/HourlyTrack.qml
import QtQuick
import Quickshell
import "../../theme"
import "../../services"

// The scrolling hour track under every Hourly style: a Flickable one column per hour, a chart canvas above a row of hour cells.
// It owns scrolling, cursor-follow, day boundaries, click selection and repaint triggers; a style supplies only the look.
// Declared children land above the canvas and below the hour cells, in content coordinates; `underlay` children go below the canvas.
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    // Called as paint(ctx, width, height) on the canvas. The painter must call ctx.reset() itself.
    property var paint: function (ctx, w, h) {}
    // Day labels for the chart: "Today" and "Tue", or "TODAY" and "TUE".
    property bool caps_day_labels: false

    readonly property int hour_col_w: 56
    property int icon_row_h: 30
    property int label_row_h: 18
    readonly property int chart_h: root.height - root.icon_row_h - root.label_row_h - 4

    // Default hour cell: weather icon (a wind arrow on the wind sub) above the time label.
    property Component highlight: null
    property color arrow_color: Style.pal.cyan
    property color label_color: Style.text_muted
    property color label_color_selected: Style.pal.secondary
    property string label_font_family: Style.font_family
    property real label_px: Style.fs(-2)
    property bool label_bold_selected: false
    property color label_outline: "transparent"
    property bool hidpi_icons: false
    // Replaces the default cell. It sits in a Repeater, so it needs `required property var modelData` and `index`, and sets its own geometry.
    property Component cell: null

    readonly property var day_boundaries: {
        const list = [];
        let last_date = null;
        const today_str = WeatherState.location_date_str();
        const hrs = WeatherState.hours;
        for (let i = 0; i < hrs.length; i++) {
            if (hrs[i].date !== last_date) {
                let label = hrs[i].date === today_str ? "Today" : Qt.formatDate(new Date(hrs[i].date + "T00:00:00"), "ddd");
                if (root.caps_day_labels) label = label.toUpperCase();
                list.push({ index: i, label: label });
                last_date = hrs[i].date;
            }
        }
        return list;
    }

    default property alias overlay: overlay_item.data
    property alias underlay: underlay_item.data

    function value_of(row) {
        return [row.temp, row.pop, row.wind_speed, row.uv_index, row.humidity][root.sub];
    }

    function left_of(i) {
        return i * root.hour_col_w;
    }

    function x_of(i) {
        return root.left_of(i) + root.hour_col_w / 2;
    }

    function request_paint() {
        canvas.requestPaint();
    }

    function scroll_to_cursor() {
        const cursor_x = root.hour_cursor * root.hour_col_w;
        // Narrow views get a smaller lead so the two margins never overlap.
        const margin = Math.max(0, Math.min(root.hour_col_w * 2, (flick.width - root.hour_col_w) / 2));
        if (cursor_x < flick.contentX + margin) {
            flick.contentX = Math.max(0, cursor_x - margin);
        } else if (cursor_x + root.hour_col_w > flick.contentX + flick.width - margin) {
            flick.contentX = Math.min(Math.max(0, flick.contentWidth - flick.width), cursor_x + root.hour_col_w - flick.width + margin);
        }
    }

    property bool want_scroll: false

    function request_scroll() {
        if (flick.width > 0) root.scroll_to_cursor();
        else root.want_scroll = true;
    }

    onSubChanged: root.request_paint()

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: WeatherState.hours.length * root.hour_col_w
        contentHeight: height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        onContentXChanged: root.on_scroll(flick.contentX)

        onWidthChanged: {
            if (root.want_scroll && flick.width > 0) {
                root.want_scroll = false;
                root.scroll_to_cursor();
            }
        }

        Component.onCompleted: flick.contentX = root.scroll_x

        Item {
            width: flick.contentWidth
            height: flick.contentHeight

            Item {
                id: underlay_item
                anchors.fill: parent
            }

            Canvas {
                id: canvas
                width: parent.width
                height: root.chart_h
                onPaint: root.paint(getContext("2d"), width, height)
                onHeightChanged: requestPaint()

                Connections {
                    target: WeatherState
                    function onHoursChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: Style
                    function onFont_familyChanged() { canvas.requestPaint(); }
                    function onFont_sizeChanged() { canvas.requestPaint(); }
                    function onPalChanged() { canvas.requestPaint(); }
                    function onText_primaryChanged() { canvas.requestPaint(); }
                    function onText_mutedChanged() { canvas.requestPaint(); }
                }
            }

            Item {
                id: overlay_item
                anchors.fill: parent
            }

            Repeater {
                model: WeatherState.hours
                delegate: root.cell ? root.cell : default_cell
            }

            Repeater {
                model: WeatherState.hours

                MouseArea {
                    required property int index

                    x: root.left_of(index)
                    y: root.chart_h + 4
                    width: root.hour_col_w
                    height: root.icon_row_h + root.label_row_h
                    onClicked: root.on_select(index)
                }
            }
        }
    }

    Component {
        id: default_cell

        Item {
            id: hour_col
            required property var modelData
            required property int index
            readonly property bool selected: hour_col.index === root.hour_cursor

            x: root.left_of(hour_col.index)
            y: root.chart_h + 4
            width: root.hour_col_w
            height: root.icon_row_h + root.label_row_h

            Loader {
                anchors.fill: parent
                active: hour_col.selected
                sourceComponent: root.highlight
            }

            Image {
                visible: root.sub !== 2
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.icon_row_h
                height: root.icon_row_h
                readonly property real dpr: root.hidpi_icons && QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                sourceSize.width: Math.ceil(root.icon_row_h * 2 * dpr)
                sourceSize.height: Math.ceil(root.icon_row_h * 2 * dpr)
                source: WeatherState.icon_source(hour_col.modelData.code, hour_col.modelData.is_day)
                smooth: true
            }

            Text {
                visible: root.sub === 2
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -(root.label_row_h / 2)
                text: "▲"
                rotation: hour_col.modelData.wind_dir
                color: root.arrow_color
                font.pixelSize: Style.font_size
            }

            Text {
                anchors.top: parent.top
                anchors.topMargin: root.icon_row_h
                anchors.horizontalCenter: parent.horizontalCenter
                text: WeatherState.format_hour(new Date(hour_col.modelData.dt))
                color: hour_col.selected ? root.label_color_selected : root.label_color
                font.family: root.label_font_family
                font.pixelSize: root.label_px
                font.bold: root.label_bold_selected && hour_col.selected
                style: root.label_outline.a > 0 ? Text.Outline : Text.Normal
                styleColor: root.label_outline
            }
        }
    }
}
