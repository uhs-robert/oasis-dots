// home/quickshell/.config/quickshell/popups/weather/ScopeAlerts.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"

// The threat board: each active alert a tracked contact with a priority and a range (time until it arrives), the selected one decoded in the transmission panel below.
// h/l or j/k select when there's more than one; with a single alert they scroll its transmission instead (see scroll_detail, called by the popup's key handler).
Item {
    id: root

    property int alert_cursor: 0
    // Called with the clicked alert index; the popup owns alert_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real detail_y: 0
    property var on_detail_scroll: function (y) {}

    readonly property color vec: Style.text_primary
    readonly property color vec_dim: Style.text_muted
    readonly property color lock: Style.selection_brackets.a > 0 ? Style.selection_brackets : Theme.theme_label

    readonly property var alerts: WeatherState.alerts
    readonly property var selected: root.alerts[Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor))]
    readonly property int row_h: Math.round(Style.fs(-2) + Style.fs(-4) + 14)
    readonly property var weekday_names: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property var severity_order: ["Extreme", "Severe", "Moderate", "Minor"]

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

    function priority_of(alert) {
        const rank = root.severity_order.indexOf(alert.severity);
        return rank >= 0 ? rank + 1 : root.severity_order.length + 1;
    }

    // Time until the alert takes effect, or "ON STATION" once it has.
    function range_of(alert) {
        const onset = alert.onset ? new Date(alert.onset).getTime() : NaN;
        const minutes = Math.round((onset - Date.now()) / 60000);
        if (isNaN(minutes) || minutes <= 0) return "ON STATION";
        return "T-" + (minutes < 90 ? minutes + "M" : minutes < 2880 ? Math.round(minutes / 60) + "H" : Math.round(minutes / 1440) + "D");
    }

    function scroll_detail(dir) {
        detail_flick.contentY = Math.max(0, Math.min(Math.max(0, detail_flick.contentHeight - detail_flick.height), detail_flick.contentY + dir * 40));
    }

    onAlert_cursorChanged: alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain)

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: root.alerts.length === 0 ? "NO CONTACTS" : "CONTACTS · " + root.alerts.length + " TRACKED"
            color: root.alerts.length === 0 ? root.vec_dim : root.lock
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
            font.bold: true
            font.letterSpacing: 2
        }

        // At most three contacts show; the rest scroll so the transmission keeps most of the height.
        ListView {
            id: alert_list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(3, root.alerts.length) * (root.row_h + spacing)
            visible: root.alerts.length > 0
            clip: true
            spacing: 3
            boundsBehavior: Flickable.StopAtBounds
            model: root.alerts
            onCountChanged: Qt.callLater(() => alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain))

            delegate: Rectangle {
                id: contact
                required property var modelData
                required property int index
                readonly property bool is_selected: contact.index === root.alert_cursor
                readonly property color severity_color: WeatherState.alert_color(contact.modelData.severity)

                width: ListView.view.width
                height: root.row_h
                color: contact.is_selected ? Style.selection_bg : "transparent"
                border.width: 1
                border.color: Qt.alpha(root.vec, contact.is_selected ? 0.0 : 0.16)

                CornerBrackets {
                    visible: contact.is_selected
                    anchors.fill: parent
                    color: root.lock
                    inset: 0
                    arm: 7
                    thickness: 1.5
                    all_corners: true
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        text: "P" + root.priority_of(contact.modelData)
                        color: contact.severity_color
                        font.family: Style.number_font
                        font.pixelSize: Style.fs(1)
                        font.bold: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: contact.modelData.event.toUpperCase()
                            color: contact.is_selected ? Style.text_strong : root.vec
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-2)
                            font.bold: contact.is_selected
                            font.letterSpacing: 0.5
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: contact.modelData.severity.toUpperCase() + (contact.modelData.ends ? " · ENDS " + root.fmt_time(contact.modelData.ends).toUpperCase() : "")
                            color: root.vec_dim
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                            font.letterSpacing: 0.5
                        }
                    }

                    Text {
                        text: root.range_of(contact.modelData)
                        color: contact.is_selected ? root.lock : root.vec_dim
                        font.family: Style.number_font
                        font.pixelSize: Style.fs(-3)
                        font.bold: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.on_select(contact.index)
                }
            }
        }

        Text {
            visible: root.alerts.length > 0
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: "INCOMING TRANSMISSION" + (root.selected ? " · TGT " + String(Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor)) + 1).padStart(2, "0") : "")
            color: root.lock
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
            font.bold: true
            font.letterSpacing: 2
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: 4
            visible: !!root.selected

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(root.vec, 0.22)
            }

            CornerBrackets {
                anchors.fill: parent
                color: root.vec
                inset: 0
                arm: 12
                thickness: 1.5
                all_corners: true
            }

            Flickable {
                id: detail_flick
                anchors.fill: parent
                anchors.margins: 8
                anchors.rightMargin: 12
                clip: true
                contentWidth: width
                contentHeight: detail_col.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                onContentYChanged: root.on_detail_scroll(detail_flick.contentY)
                Component.onCompleted: detail_flick.contentY = root.detail_y

                ColumnLayout {
                    id: detail_col
                    width: detail_flick.width
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.selected ? root.selected.headline || root.selected.event : ""
                        color: Style.text_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.selected ? "EFFECTIVE " + root.fmt_time(root.selected.onset) + "  ·  ENDS " + root.fmt_time(root.selected.ends) : ""
                        color: root.lock
                        font.family: Style.number_font
                        font.pixelSize: Style.fs(-3)
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.selected ? "SECTOR " + root.selected.area : ""
                        color: root.vec_dim
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-3)
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        Layout.preferredHeight: 1
                        color: Qt.alpha(root.vec, 0.22)
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        wrapMode: Text.WordWrap
                        text: root.selected ? root.unwrap(root.selected.description) : ""
                        color: root.vec
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        visible: !!root.selected && root.selected.instruction !== ""
                        text: "ORDERS"
                        color: root.lock
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-4)
                        font.bold: true
                        font.letterSpacing: 2
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !!root.selected && root.selected.instruction !== ""
                        wrapMode: Text.WordWrap
                        text: root.selected ? root.unwrap(root.selected.instruction) : ""
                        color: root.vec
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                    }
                }
            }

            // Scroll position as a thin lock-coloured slider, shown only when the transmission overflows.
            Rectangle {
                visible: detail_flick.contentHeight > detail_flick.height
                x: parent.width - 8
                y: 8
                width: 2
                height: parent.height - 16
                color: Qt.alpha(root.vec, 0.18)

                Rectangle {
                    width: parent.width
                    height: Math.max(10, parent.height * detail_flick.height / detail_flick.contentHeight)
                    y: (parent.height - height) * (detail_flick.contentY / Math.max(1, detail_flick.contentHeight - detail_flick.height))
                    color: root.lock
                }
            }
        }

        Text {
            visible: root.alerts.length === 0
            text: "NO INCOMING TRANSMISSIONS"
            color: Style.text_dim
            font.family: Style.font_family
            font.pixelSize: Style.fs(-1)
            font.letterSpacing: 1.5
        }
    }
}
