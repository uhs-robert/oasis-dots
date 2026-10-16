import QtQuick
import QtQuick.Layouts
import qs.components
import qs.theme
import qs.services

// Active NWS alerts as a Dragon Quest encounter: an "appears!" message for the selected alert, the alerts as the enemy list
// (severity is the enemy's level) and the alert text as battle message text. h/l or j/k select when there's more than one;
// with a single alert they scroll its text instead (see scroll_detail, called by the popup's key handler).
Item {
    id: root

    property int alert_cursor: 0
    // Called with the clicked alert index; the popup owns alert_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real detail_y: 0
    property var on_detail_scroll: function (y) {}

    readonly property var alerts: WeatherState.alerts
    readonly property var selected: root.alerts[Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor))]

    readonly property var weekday_names: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property var severity_levels: ({ Extreme: 4, Severe: 3, Moderate: 2, Minor: 1 })

    // The pixel font's ascenders and descenders touch at its natural line height.
    readonly property int line_h: Style.fs(-2) + 6
    readonly property int row_h: Style.fs(-2) + 10
    readonly property bool more_below: detail_flick.contentHeight - detail_flick.height - detail_flick.contentY > 2
    readonly property bool more_above: detail_flick.contentY > 2

    function level_of(alert) {
        return root.severity_levels[alert.severity] || 0;
    }

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

    function appears_line(alert) {
        if (!alert) return "";
        return (/^[aeiou]/i.test(alert.event) ? "An " : "A ") + alert.event + " appears!";
    }

    function scroll_detail(dir) {
        detail_flick.contentY = Math.max(0, Math.min(Math.max(0, detail_flick.contentHeight - detail_flick.height), detail_flick.contentY + dir * 40));
    }

    onAlert_cursorChanged: alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain)

    DqWindow {
        anchors.fill: parent
        visible: root.alerts.length === 0

        Text {
            anchors.centerIn: parent
            text: "No active alerts"
            color: Style.text_dim
            font.family: Style.font_family
            font.pixelSize: Style.fs(-1)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        visible: root.alerts.length > 0

        DqWindow {
            Layout.fillWidth: true
            implicitHeight: appears.implicitHeight + 22

            ColumnLayout {
                id: appears
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.appears_line(root.selected)
                    color: Style.pal.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-2)
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.selected ? root.fmt_time(root.selected.onset) + " – " + root.fmt_time(root.selected.ends) : ""
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                }
            }
        }

        // At most three enemies show; the rest scroll so the message keeps most of the height.
        DqWindow {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(3, root.alerts.length) * root.row_h + 22
            title: root.alerts.length > 1 ? "ENEMIES " + root.alerts.length : "ENEMY"

            ListView {
                id: alert_list
                anchors.fill: parent
                anchors.margins: 11
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.alerts
                onCountChanged: Qt.callLater(() => alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain))

                delegate: Item {
                    id: enemy
                    required property var modelData
                    required property int index
                    readonly property bool selected: enemy.index === root.alert_cursor

                    width: ListView.view.width
                    height: root.row_h

                    RowLayout {
                        anchors.fill: parent
                        spacing: 6

                        Text {
                            Layout.preferredWidth: Style.fs(-2)
                            text: Style.row_cursor
                            color: Style.caret_color
                            opacity: enemy.selected && Style.caret_phase ? 1 : 0
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-3)
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: enemy.modelData.event.toUpperCase()
                            color: enemy.selected ? Style.pal.fg_strong : Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-3)
                        }

                        Text {
                            text: "LV" + root.level_of(enemy.modelData) + " " + enemy.modelData.severity.toUpperCase()
                            color: WeatherState.alert_color(enemy.modelData.severity)
                            opacity: enemy.selected ? 1 : 0.7
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-5)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(enemy.index)
                    }
                }
            }
        }

        DqWindow {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                id: detail_flick
                anchors.fill: parent
                anchors.margins: 11
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
                        color: root.selected ? WeatherState.alert_color(root.selected.severity) : Style.pal.fg
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                        font.bold: true
                        lineHeight: root.line_h
                        lineHeightMode: Text.FixedHeight
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.selected ? root.selected.area : ""
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-3)
                        lineHeight: root.line_h
                        lineHeightMode: Text.FixedHeight
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        wrapMode: Text.WordWrap
                        text: root.selected ? root.unwrap(root.selected.description) : ""
                        color: Style.pal.fg
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                        lineHeight: root.line_h
                        lineHeightMode: Text.FixedHeight
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        visible: !!root.selected && root.selected.instruction !== ""
                        wrapMode: Text.WordWrap
                        text: root.selected ? "What to do: " + root.unwrap(root.selected.instruction) : ""
                        color: Style.pal.fg
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                        lineHeight: root.line_h
                        lineHeightMode: Text.FixedHeight
                    }
                }
            }

            // Battle text prompts: a blinking arrow where the message continues.
            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 8
                anchors.bottomMargin: 4
                visible: root.more_below && Style.caret_phase
                text: "▼"
                color: Style.pal.fg_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }

            Text {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 8
                anchors.topMargin: 4
                visible: root.more_above
                text: "▲"
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }
        }
    }
}
