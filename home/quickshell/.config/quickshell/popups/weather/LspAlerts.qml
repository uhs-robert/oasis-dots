import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services

// Active NWS alerts as a Trouble.nvim panel: the alerts as diagnostics (E W I H, event, until time), the selected one's
// full text in a hover float below it, and a statusline footer. h/l or j/k select when there's more than one; with a single
// alert they scroll its detail instead (see scroll_detail, called by the popup's key handler).
Item {
    id: root

    property int alert_cursor: 0
    // Called with the clicked alert index; the popup owns alert_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real detail_y: 0
    property var on_detail_scroll: function (y) {}

    readonly property var alerts: WeatherState.alerts
    readonly property int cursor_index: Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor))
    readonly property var selected: root.alerts[root.cursor_index]

    readonly property int text_px: Style.fs(-3)
    readonly property real line_h: Math.max(1, Math.ceil(metrics.height))
    readonly property real row_h: root.line_h + 8
    readonly property real scroll_max: Math.max(0, detail_flick.contentHeight - detail_flick.height)
    readonly property int scroll_percent: root.scroll_max > 0 ? Math.round(detail_flick.contentY / root.scroll_max * 100) : 0

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
        detail_flick.contentY = Math.max(0, Math.min(root.scroll_max, detail_flick.contentY + dir * 40));
    }

    // Severity as a diagnostic: error, warning, info, hint.
    function sign_of(severity) {
        return severity === "Extreme" || severity === "Severe" ? 0 : severity === "Moderate" ? 1 : severity === "Minor" ? 2 : 3;
    }

    readonly property var sign_letters: ["E", "W", "I", "H"]
    readonly property var sign_colors: [Style.pal.error, Style.pal.warning, Style.pal.info, Theme.hint]

    onCursor_indexChanged: alert_list.positionViewAtIndex(root.cursor_index, ListView.Contain)

    FontMetrics {
        id: metrics
        font.family: Style.mono_font
        font.pixelSize: root.text_px
    }

    Text {
        visible: root.alerts.length === 0
        anchors.centerIn: parent
        text: "✓ no diagnostics"
        color: Theme.ok
        font.family: Style.mono_font
        font.pixelSize: Style.fs(-1)
        font.italic: true
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6
        visible: root.alerts.length > 0

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: "<font color=\"" + Style.pal.primary + "\"><b>Diagnostics</b></font><font color=\"" + Style.text_dim + "\"> (weather.gov " + root.alerts.length + ")</font>"
            color: Style.text_fg
            font.family: Style.mono_font
            font.pixelSize: root.text_px
        }

        // At most four rows show; the rest scroll so the float keeps most of the height.
        ListView {
            id: alert_list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(4, root.alerts.length) * root.row_h
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.alerts
            onCountChanged: Qt.callLater(() => alert_list.positionViewAtIndex(root.cursor_index, ListView.Contain))

            delegate: Rectangle {
                id: alert_row
                required property var modelData
                required property int index
                readonly property bool current: alert_row.index === root.cursor_index
                readonly property int sign: root.sign_of(alert_row.modelData.severity)

                width: ListView.view.width
                height: root.row_h
                color: alert_row.current ? Style.selection_bg : "transparent"

                Rectangle {
                    visible: alert_row.current
                    width: 2
                    height: parent.height
                    color: Style.caret_color
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        text: root.sign_letters[alert_row.sign]
                        color: root.sign_colors[alert_row.sign]
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: alert_row.modelData.event
                        color: alert_row.current ? Style.text_strong : Style.text_fg
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                        font.bold: alert_row.current
                    }

                    Text {
                        text: alert_row.modelData.ends ? "until " + root.fmt_time(alert_row.modelData.ends) : alert_row.modelData.severity.toLowerCase()
                        color: Style.text_dim
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                        font.italic: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.on_select(alert_row.index)
                }
            }
        }

        // vim.lsp.buf.hover(): the selected alert in a rounded float, scrolled with the popup's keys.
        Rectangle {
            id: float_win
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 2
            Layout.rightMargin: 2
            radius: Style.radius(6)
            color: Style.pal.bg_surface
            border.width: 1
            border.color: root.selected ? root.sign_colors[root.sign_of(root.selected.severity)] : Style.frame_border_color

            Text {
                x: 12
                y: -height / 2
                topPadding: 0
                leftPadding: 4
                rightPadding: 4
                width: Math.min(implicitWidth, parent.width - 24)
                elide: Text.ElideRight
                text: root.selected ? root.selected.event : ""
                color: Style.text_strong
                font.family: Style.mono_font
                font.pixelSize: root.text_px
                font.bold: true
                Rectangle {
                    z: -1
                    anchors.fill: parent
                    color: Style.frame_color
                }
            }

            Flickable {
                id: detail_flick
                anchors.fill: parent
                anchors.margins: 8
                anchors.topMargin: 12
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
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.selected ? root.selected.headline || root.selected.event : ""
                        color: root.selected ? WeatherState.alert_color(root.selected.severity) : Style.text_fg
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.selected ? root.fmt_time(root.selected.onset) + " – " + root.fmt_time(root.selected.ends) + "  ·  " + root.selected.area : ""
                        color: Style.text_dim
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                        font.italic: true
                    }

                    Text {
                        Layout.topMargin: 6
                        text: "# DESCRIPTION"
                        color: Style.pal.primary
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.selected ? root.unwrap(root.selected.description) : ""
                        color: Style.text_fg
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                    }

                    Text {
                        Layout.topMargin: 6
                        visible: !!root.selected && root.selected.instruction !== ""
                        text: "# INSTRUCTIONS"
                        color: Style.pal.primary
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !!root.selected && root.selected.instruction !== ""
                        wrapMode: Text.WordWrap
                        text: root.selected ? root.unwrap(root.selected.instruction) : ""
                        color: Style.text_fg
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                    }
                }
            }

            // Scrollbar thumb inside the right border.
            Rectangle {
                visible: root.scroll_max > 0
                x: parent.width - 8
                width: 3
                radius: 1.5
                y: 12 + detail_flick.contentY / Math.max(1, detail_flick.contentHeight) * detail_flick.height
                height: Math.max(12, detail_flick.height * detail_flick.height / Math.max(1, detail_flick.contentHeight))
                color: Style.text_muted
            }
        }

        // Statusline: mode block, position among the alerts, and how far the float is scrolled.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.line_h + 6
            color: Style.pal.bg_surface

            Row {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    width: mode_text.implicitWidth + 16
                    height: parent.height
                    color: Style.pal.primary

                    Text {
                        id: mode_text
                        anchors.centerIn: parent
                        text: "ALERTS"
                        color: Style.frame_color
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                        font.bold: true
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 8
                    text: (root.cursor_index + 1) + "/" + root.alerts.length + (root.selected ? "  " + root.selected.sender : "")
                    width: parent.width - mode_text.implicitWidth - 16 - pct.implicitWidth - 8
                    elide: Text.ElideRight
                    color: Style.text_fg
                    font.family: Style.mono_font
                    font.pixelSize: root.text_px
                }

                Text {
                    id: pct
                    anchors.verticalCenter: parent.verticalCenter
                    rightPadding: 8
                    text: root.scroll_max > 0 ? root.scroll_percent + "%" : "All"
                    color: Style.text_dim
                    font.family: Style.mono_font
                    font.pixelSize: root.text_px
                }
            }
        }
    }
}
