import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"

// Active NWS alerts as a Black Mesa announcement board: severity as an alert level, the selected announcement's full text
// in a monitor. h/l or j/k select when there's more than one; with a single alert they scroll its text instead
// (see scroll_detail, called by the popup's key handler).
Item {
    id: root

    property int alert_cursor: 0
    // Called with the clicked alert index; the popup owns alert_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real detail_y: 0
    property var on_detail_scroll: function (y) {}

    readonly property var alerts: WeatherState.alerts
    readonly property var selected: root.alerts[Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor))]

    readonly property color hl: Style.text_primary
    readonly property color hl_t: Style.text_muted
    readonly property color red: Theme.theme_label
    readonly property int row_h: Style.px(36)

    readonly property var weekday_names: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property var level_by_severity: ({ "Extreme": 4, "Severe": 3, "Moderate": 2, "Minor": 1 })

    function alert_level(severity) {
        return root.level_by_severity[severity] || 0;
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

    function scroll_detail(dir) {
        detail_flick.contentY = Math.max(0, Math.min(Math.max(0, detail_flick.contentHeight - detail_flick.height), detail_flick.contentY + dir * 40));
    }

    onAlert_cursorChanged: alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain)

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: head_row.implicitHeight + 4
            color: Qt.alpha(root.red, 0.85)

            RowLayout {
                id: head_row
                x: 8
                width: parent.width - 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: "BLACK MESA ANNOUNCEMENT SYSTEM"
                    color: Style.pal.bg_crust
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-6)
                    font.bold: true
                    font.letterSpacing: root.width >= 300 ? 2.8 : 1
                }

                Text {
                    text: root.alerts.length + " ACTIVE"
                    color: Style.pal.bg_crust
                    font.family: Style.number_font
                    font.pixelSize: Style.fs(-5)
                    font.bold: true
                    font.letterSpacing: 1
                }
            }
        }

        Text {
            visible: root.alerts.length === 0
            Layout.topMargin: 4
            text: "NO ACTIVE ANNOUNCEMENTS"
            color: Style.text_dim
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
            font.bold: true
            font.letterSpacing: 2
        }

        Item {
            visible: root.alerts.length === 0
            Layout.fillHeight: true
        }

        // At most three rows show; the rest scroll so the monitor keeps most of the height.
        ListView {
            id: alert_list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(3, root.alerts.length) * (root.row_h + spacing)
            visible: root.alerts.length > 0
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.alerts
            onCountChanged: Qt.callLater(() => alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain))

            delegate: MenuRow {
                id: alert_row
                required property var modelData
                required property int index
                readonly property color level_color: WeatherState.alert_color(alert_row.modelData.severity)

                width: ListView.view.width
                height: root.row_h
                selected: alert_row.index === root.alert_cursor

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    anchors.leftMargin: 8 + alert_row.inset
                    anchors.rightMargin: 8 + alert_row.key_space
                    spacing: 8

                    ColumnLayout {
                        spacing: 1
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: alert_row.modelData.event.toUpperCase()
                            color: alert_row.fg(alert_row.level_color)
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-3)
                            font.bold: true
                            font.letterSpacing: 0.8
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: alert_row.modelData.ends ? WeatherState.fmt_until(alert_row.modelData.ends).toUpperCase() : "NO END TIME"
                            color: alert_row.fg(root.hl_t)
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-5)
                            font.letterSpacing: 0.8
                        }
                    }

                    ColumnLayout {
                        spacing: 2
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: "LEVEL " + root.alert_level(alert_row.modelData.severity)
                            color: alert_row.fg(alert_row.level_color)
                            font.family: Style.number_font
                            font.pixelSize: Style.fs(-5)
                            font.bold: true
                            font.letterSpacing: 1.5
                        }

                        SkewBar {
                            Layout.preferredWidth: 52
                            Layout.preferredHeight: 7
                            cells: 4
                            gap: 1.5
                            value: root.alert_level(alert_row.modelData.severity) / 4
                            on_color: alert_row.level_color
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.on_select(alert_row.index)
                }
            }
        }

        Rectangle {
            visible: !!root.selected
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.bg_crust
            border.width: 1
            border.color: Style.hairline

            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                color: "transparent"
                border.width: 1
                border.color: Style.hairline_dim
            }

            Flickable {
                id: detail_flick
                anchors.fill: parent
                anchors.margins: 9
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
                        text: root.selected ? "ATTENTION: " + root.selected.event.toUpperCase() : ""
                        color: root.selected ? WeatherState.alert_color(root.selected.severity) : root.hl
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-1)
                        font.bold: true
                        font.letterSpacing: 1.5
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !!root.selected && !!root.selected.headline
                        wrapMode: Text.WordWrap
                        text: root.selected ? root.selected.headline : ""
                        color: root.hl
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-3)
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.selected ? "EFFECTIVE " + root.fmt_time(root.selected.onset).toUpperCase() + "  ·  ENDS " + root.fmt_time(root.selected.ends).toUpperCase() : ""
                        color: root.hl_t
                        font.family: Style.number_font
                        font.pixelSize: Style.fs(-4)
                        font.bold: true
                        font.letterSpacing: 0.8
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !!root.selected && root.selected.area !== ""
                        wrapMode: Text.Wrap
                        text: root.selected ? root.selected.area : ""
                        color: root.hl_t
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-4)
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        Layout.preferredHeight: 1
                        color: Style.hairline_dim
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        wrapMode: Text.WordWrap
                        text: root.selected ? root.unwrap(root.selected.description) : ""
                        color: root.hl
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        visible: !!root.selected && root.selected.instruction !== ""
                        wrapMode: Text.WordWrap
                        text: root.selected ? "ALL PERSONNEL: " + root.unwrap(root.selected.instruction) : ""
                        color: root.red
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                    }
                }
            }

            // Where the visible text sits in the announcement, for when it runs past the monitor.
            Rectangle {
                visible: detail_flick.contentHeight > detail_flick.height
                x: parent.width - 6
                y: 9 + (detail_flick.height - height) * (detail_flick.contentY / Math.max(1, detail_flick.contentHeight - detail_flick.height))
                width: 2
                height: Math.max(16, detail_flick.height * detail_flick.height / detail_flick.contentHeight)
                color: Style.hairline
            }
        }
    }
}
