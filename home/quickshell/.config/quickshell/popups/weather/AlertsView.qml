// home/quickshell/.config/quickshell/popups/weather/AlertsView.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"

// Active NWS alerts. h/l or j/k select when there's more than one; with a single alert
// they scroll its detail text instead (see scroll_detail, called by the popup's key handler).
Item {
    id: root

    property int alert_cursor: 0
    // Called with the clicked alert index; the popup owns alert_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property var alerts: WeatherState.alerts
    readonly property var selected: root.alerts[Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor))]

    readonly property var weekday_names: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

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

    function scroll_detail(dir) {
        detail_flick.contentY = Math.max(0, Math.min(Math.max(0, detail_flick.contentHeight - detail_flick.height), detail_flick.contentY + dir * 40));
    }

    readonly property int row_h: Style.px(36)

    onAlert_cursorChanged: alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain)

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            visible: root.alerts.length === 0
            text: "No active alerts"
            color: Style.text_dim
            font.family: Style.font_family
            font.pixelSize: Style.font_size - 1
        }

        // At most three rows show; the rest scroll so the detail keeps most of the height.
        ListView {
            id: alert_list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(3, root.alerts.length) * (root.row_h + spacing)
            visible: root.alerts.length > 0
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.alerts

            delegate: MenuRow {
                id: alert_row
                required property var modelData
                required property int index

                width: ListView.view.width
                height: root.row_h
                selected: alert_row.index === root.alert_cursor

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    anchors.leftMargin: 4 + alert_row.inset
                    anchors.rightMargin: 4 + alert_row.key_space
                    spacing: 6

                    Rectangle {
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        radius: Style.radius(3)
                        color: WeatherState.alert_color(alert_row.modelData.severity)
                    }

                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: alert_row.modelData.event
                            color: alert_row.fg(alert_row.index === root.alert_cursor ? Theme.theme_secondary : Theme.fg_core)
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size - 2
                        }
                        Text {
                            text: alert_row.modelData.severity
                            color: alert_row.fg(Style.text_muted)
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size - 4
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.on_select(alert_row.index)
                }
            }
        }

        Flickable {
            id: detail_flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: detail_col.implicitHeight
            visible: !!root.selected

            ColumnLayout {
                id: detail_col
                width: detail_flick.width
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.selected ? root.selected.headline || root.selected.event : ""
                    color: root.selected ? WeatherState.alert_color(root.selected.severity) : Theme.fg_core
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.selected ? root.fmt_time(root.selected.onset) + " – " + root.fmt_time(root.selected.ends) + "  ·  " + root.selected.area : ""
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size - 3
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    wrapMode: Text.WordWrap
                    text: root.selected ? root.unwrap(root.selected.description) : ""
                    color: Theme.fg_core
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size - 2
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    visible: !!root.selected && root.selected.instruction !== ""
                    wrapMode: Text.WordWrap
                    text: root.selected ? "What to do: " + root.unwrap(root.selected.instruction) : ""
                    color: Theme.fg_core
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size - 2
                }
            }
        }
    }
}
