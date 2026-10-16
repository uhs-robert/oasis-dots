import QtQuick
import QtQuick.Layouts
import qs.components.oasis as Oasis
import qs.theme
import qs.services

// Oasis Alerts: notices as a stack of cards tinted by severity. With several alerts the others sit as short cards
// above the selected one, which opens with its full text; with one, h/l scroll that text (see scroll_detail, called
// by the popup's key handler).
Item {
    id: root

    property int alert_cursor: 0
    // Called with the clicked alert index; the popup owns alert_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real detail_y: 0
    property var on_detail_scroll: function (y) {}

    readonly property color sand: Theme.theme_secondary
    readonly property var alerts: WeatherState.alerts
    readonly property var selected: root.alerts[Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor))]
    readonly property color selected_color: root.selected ? WeatherState.alert_color(root.selected.severity) : Style.text_dim

    readonly property var weekday_names: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property real row_h: Style.px(40)

    function is_critical(alert) {
        return alert.severity === "Extreme" || alert.severity === "Severe";
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

    Text {
        visible: root.alerts.length === 0
        anchors.centerIn: parent
        text: "No active alerts"
        color: Style.text_dim
        font.family: Style.font_family
        font.pixelSize: Style.fs(-1)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6
        visible: root.alerts.length > 0

        // At most three cards show; the rest scroll so the open notice keeps most of the height.
        ListView {
            id: alert_list
            Layout.fillWidth: true
            Layout.preferredHeight: root.alerts.length > 1 ? Math.min(3, root.alerts.length) * (root.row_h + spacing) - spacing : 0
            visible: root.alerts.length > 1
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: root.alerts
            onCountChanged: Qt.callLater(() => alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain))

            delegate: Oasis.OasisCard {
                id: notice
                required property var modelData
                required property int index
                readonly property color tint: WeatherState.alert_color(notice.modelData.severity)

                width: ListView.view.width
                height: root.row_h
                selected: notice.index === root.alert_cursor
                critical: root.is_critical(notice.modelData)

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Qt.alpha(notice.tint, notice.selected ? 0.12 : 0.07)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        radius: 4
                        color: notice.tint
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: notice.modelData.event
                            color: notice.selected ? Style.text_strong : Theme.fg_core
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-2)
                            font.weight: notice.selected ? Font.DemiBold : Font.Medium
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: notice.modelData.severity + (notice.modelData.ends ? " · until " + root.fmt_time(notice.modelData.ends) : "")
                            color: Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.on_select(notice.index)
                }
            }
        }

        Oasis.OasisCard {
            id: open_card
            Layout.fillWidth: true
            Layout.fillHeight: true
            selected: root.alerts.length > 1
            critical: !!root.selected && root.is_critical(root.selected)

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Qt.alpha(root.selected_color, 0.09)
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 10
                anchors.bottomMargin: 8
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: chip_text.implicitWidth + 14
                        Layout.preferredHeight: chip_text.implicitHeight + 4
                        radius: height / 2
                        color: Qt.alpha(root.selected_color, 0.2)
                        border.width: 1
                        border.color: Qt.alpha(root.selected_color, 0.6)

                        Text {
                            id: chip_text
                            anchors.centerIn: parent
                            text: root.selected ? root.selected.severity.toUpperCase() : ""
                            color: root.selected_color
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.2
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: root.selected ? root.selected.event : ""
                        color: Style.text_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(1)
                        font.weight: Font.DemiBold
                    }
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.selected ? root.fmt_time(root.selected.onset) + " – " + root.fmt_time(root.selected.ends) : ""
                    color: root.sand
                    font.family: Style.number_font
                    font.pixelSize: Style.fs(-2)
                    font.features: { "tnum": 1 }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    implicitHeight: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.alpha(root.sand, 0.45) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }

                Flickable {
                    id: detail_flick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
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
                            Layout.topMargin: 4
                            wrapMode: Text.WordWrap
                            text: root.selected ? root.selected.headline || root.selected.event : ""
                            color: root.selected_color
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size
                            font.bold: true
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: root.selected ? root.selected.area : ""
                            color: Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-3)
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            wrapMode: Text.WordWrap
                            text: root.selected ? root.unwrap(root.selected.description) : ""
                            color: Style.pal.fg
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-2)
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            visible: !!root.selected && root.selected.instruction !== ""
                            wrapMode: Text.WordWrap
                            text: root.selected ? "What to do: " + root.unwrap(root.selected.instruction) : ""
                            color: root.sand
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-2)
                        }
                    }
                }
            }
        }
    }
}
