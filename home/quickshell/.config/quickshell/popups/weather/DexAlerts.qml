// home/quickshell/.config/quickshell/popups/weather/DexAlerts.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"

// Active NWS alerts as Pokémon boxes: "A wild FLOOD WATCH appeared!", the alerts as the party list, the selected one's text in a paging text box.
// h/l or j/k select when there's more than one; with a single alert they page its text instead (see scroll_detail, called by the popup's key handler).
Item {
    id: root

    property int alert_cursor: 0
    // Called with the clicked alert index; the popup owns alert_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real detail_y: 0
    property var on_detail_scroll: function (y) {}

    readonly property var shades: Style.pixel_shades
    readonly property var alerts: WeatherState.alerts
    readonly property var selected: root.alerts[Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor))]

    readonly property var weekday_names: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    // How full a severity's HP-style bar is: the worse the alert, the fuller.
    readonly property var severity_level: ({ Extreme: 1, Severe: 0.75, Moderate: 0.5, Minor: 0.25 })

    readonly property int row_h: 20
    readonly property int line_h: 12
    // The text box pages in whole lines; h/l move it this many at a time.
    readonly property int page_lines: 3

    function fmt_time(iso) {
        if (!iso) return "—";
        const d = new Date(iso);
        const shifted = new Date(d.getTime() + WeatherState.utc_offset * 1000);
        const day = shifted.toISOString().substr(0, 10) === WeatherState.location_date_str() ? "" : root.weekday_names[shifted.getUTCDay()] + " ";
        return day + WeatherState.fmt_location_time(d);
    }

    // NWS hard-wraps prose near 70 columns; only join a line that continues in lowercase,
    // so tables, lists and headings keep their breaks.
    function unwrap(text) {
        return (text || "").replace(/-\n(?=[a-z])/g, "-").replace(/([^\n])\n(?=[a-z])/g, "$1 ");
    }

    function level_of(severity) {
        return root.severity_level[severity] || 0.1;
    }

    function scroll_detail(dir) {
        const max_y = Math.max(0, detail_flick.contentHeight - detail_flick.height);
        detail_flick.contentY = Math.max(0, Math.min(max_y, detail_flick.contentY + dir * root.page_lines * root.line_h));
    }

    onAlert_cursorChanged: alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain)

    Text {
        anchors.centerIn: parent
        visible: root.alerts.length === 0
        text: "NO ACTIVE ALERTS"
        color: root.shades[2]
        font.family: Style.font_family
        font.pixelSize: 8
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        visible: root.alerts.length > 0

        TextBox {
            Layout.fillWidth: true
            rich: true
            font_size: 8
            readonly property string event: root.selected ? root.selected.event.toUpperCase().replace(/&/g, "&amp;").replace(/</g, "&lt;") : ""
            text: "A wild <b>" + event + "</b> appeared!" + (root.alerts.length > 1 ? " (" + (Math.min(root.alerts.length - 1, root.alert_cursor) + 1) + "/" + root.alerts.length + ")" : "")
        }

        // At most three rows show; the rest scroll so the text keeps most of the height.
        PixelBox {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(3, root.alerts.length) * (root.row_h + alert_list.spacing) - alert_list.spacing + 2 * edge + 8
            fill: root.shades[0]
            rings: [root.shades[2], root.shades[0]]

            ListView {
                id: alert_list
                anchors.fill: parent
                anchors.margins: parent.edge + 2
                clip: true
                spacing: 0
                boundsBehavior: Flickable.StopAtBounds
                interactive: false
                model: root.alerts
                onCountChanged: Qt.callLater(() => alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain))

                delegate: Item {
                    id: alert_row
                    required property var modelData
                    required property int index
                    readonly property bool current: alert_row.index === root.alert_cursor

                    width: ListView.view.width
                    height: root.row_h

                    Rectangle {
                        anchors.fill: parent
                        color: alert_row.current ? root.shades[1] : "transparent"
                    }

                    // The party cursor: a stepped right-pointing triangle.
                    Item {
                        visible: alert_row.current
                        x: 6
                        y: Math.round((parent.height - 8) / 2)
                        width: 6
                        height: 8
                        Rectangle { x: 0; y: 0; width: 2; height: 8; color: root.shades[3] }
                        Rectangle { x: 2; y: 1; width: 2; height: 6; color: root.shades[3] }
                        Rectangle { x: 4; y: 2; width: 2; height: 4; color: root.shades[3] }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        anchors.right: severity_text.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: alert_row.modelData.event.toUpperCase()
                        color: alert_row.current ? root.shades[3] : root.shades[2]
                        font.family: Style.font_family
                        font.pixelSize: 8
                    }

                    Text {
                        id: severity_text
                        anchors.right: hp_bar.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: alert_row.modelData.severity.toUpperCase()
                        color: alert_row.current ? root.shades[3] : root.shades[2]
                        font.family: Style.font_family
                        font.pixelSize: 8
                    }

                    DexStatBar {
                        id: hp_bar
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 48
                        value: root.level_of(alert_row.modelData.severity)
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(alert_row.index)
                    }
                }
            }
        }

        PixelBox {
            Layout.fillWidth: true
            Layout.fillHeight: true
            fill: root.shades[0]
            rings: [root.shades[2], root.shades[0], root.shades[3]]

            Flickable {
                id: detail_flick
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: parent.edge + 4
                anchors.rightMargin: parent.edge + 14
                // Whole lines only, so a page never ends on half a line.
                height: Math.max(root.line_h, Math.floor((parent.height - 2 * (parent.edge + 4)) / root.line_h) * root.line_h)
                clip: true
                interactive: false
                contentWidth: width
                contentHeight: Math.ceil(detail_col.implicitHeight / root.line_h) * root.line_h
                onContentYChanged: root.on_detail_scroll(detail_flick.contentY)
                Component.onCompleted: detail_flick.contentY = root.detail_y

                ColumnLayout {
                    id: detail_col
                    width: detail_flick.width
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        lineHeight: root.line_h
                        lineHeightMode: Text.FixedHeight
                        text: root.selected ? root.selected.headline || root.selected.event : ""
                        color: root.shades[3]
                        font.family: Style.font_family
                        font.pixelSize: 8
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        lineHeight: root.line_h
                        lineHeightMode: Text.FixedHeight
                        text: root.selected ? root.fmt_time(root.selected.onset).toUpperCase() + " – " + root.fmt_time(root.selected.ends).toUpperCase() + " · " + root.selected.area : ""
                        color: root.shades[2]
                        font.family: Style.font_family
                        font.pixelSize: 8
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: root.line_h
                        wrapMode: Text.WordWrap
                        lineHeight: root.line_h
                        lineHeightMode: Text.FixedHeight
                        text: root.selected ? root.unwrap(root.selected.description) : ""
                        color: root.shades[3]
                        font.family: Style.font_family
                        font.pixelSize: 8
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: root.line_h
                        visible: !!root.selected && root.selected.instruction !== ""
                        wrapMode: Text.WordWrap
                        lineHeight: root.line_h
                        lineHeightMode: Text.FixedHeight
                        text: root.selected ? "What to do: " + root.unwrap(root.selected.instruction) : ""
                        color: root.shades[3]
                        font.family: Style.font_family
                        font.pixelSize: 8
                    }
                }
            }

            readonly property bool more_below: detail_flick.contentY + detail_flick.height < detail_flick.contentHeight - 1
            readonly property bool more_above: detail_flick.contentY > 0

            Text {
                visible: parent.more_below && Style.caret_phase
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 9
                anchors.bottomMargin: 7
                text: "▼"
                color: root.shades[3]
                font.family: "Press Start 2P"
                font.pixelSize: 8
            }

            Text {
                visible: parent.more_above
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 9
                anchors.topMargin: 7
                text: "▲"
                color: root.shades[2]
                font.family: "Press Start 2P"
                font.pixelSize: 8
            }

            MouseArea {
                anchors.fill: parent
                onWheel: wheel => root.scroll_detail(wheel.angleDelta.y < 0 ? 1 : -1)
            }
        }
    }
}
