// home/quickshell/.config/quickshell/popups/weather/AlertsView.qml
import QtQuick
import QtQuick.Layouts
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

    function fmt_time(iso) {
        if (!iso) return "—";
        const d = new Date(iso);
        return WeatherState.fmt_location_time(d);
    }

    function scroll_detail(dir) {
        detail_flick.contentY = Math.max(0, Math.min(Math.max(0, detail_flick.contentHeight - detail_flick.height), detail_flick.contentY + dir * 40));
    }

    RowLayout {
        anchors.fill: parent
        spacing: 14

        ColumnLayout {
            Layout.preferredWidth: 200
            Layout.fillHeight: true
            spacing: 2

            Text {
                visible: root.alerts.length === 0
                text: "No active alerts"
                color: Theme.fg_dim
                font.family: Theme.font_family
                font.pixelSize: Theme.popup_font_size - 1
            }

            Repeater {
                model: root.alerts

                Rectangle {
                    id: alert_row
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    height: 36
                    radius: 4
                    color: alert_row.index === root.alert_cursor ? Theme.bg_surface : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 6

                        Rectangle {
                            Layout.preferredWidth: 6
                            Layout.preferredHeight: 6
                            radius: 3
                            color: WeatherState.alert_color(alert_row.modelData.severity)
                        }

                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: alert_row.modelData.event
                                color: alert_row.index === root.alert_cursor ? Theme.theme_secondary : Theme.fg_core
                                font.family: Theme.font_family
                                font.pixelSize: Theme.popup_font_size - 2
                            }
                            Text {
                                text: alert_row.modelData.severity
                                color: Theme.fg_muted
                                font.family: Theme.font_family
                                font.pixelSize: Theme.popup_font_size - 4
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(alert_row.index)
                    }
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
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: root.selected ? root.fmt_time(root.selected.onset) + " – " + root.fmt_time(root.selected.ends) + "  ·  " + root.selected.area : ""
                    color: Theme.fg_muted
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size - 3
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    wrapMode: Text.WordWrap
                    text: root.selected ? root.selected.description : ""
                    color: Theme.fg_core
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size - 2
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    visible: !!root.selected && root.selected.instruction !== ""
                    wrapMode: Text.WordWrap
                    text: root.selected ? "What to do: " + root.selected.instruction : ""
                    color: Theme.fg_core
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size - 2
                }
            }
        }
    }
}
