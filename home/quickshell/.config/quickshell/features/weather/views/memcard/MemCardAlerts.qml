import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.features.weather

// Active NWS alerts as the memory card manager: each alert a save in the card's slot list, its icon the severity and
// its blocks the severity level, with the selected save's info panel holding the full text. With a single alert the
// popup's h/l scroll that panel instead (see scroll_detail).
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
    readonly property int row_h: 48
    readonly property int severity_levels: 4

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

    // A save's size in blocks: how severe the alert is, from 1 (minor or unrated) to 4 (extreme).
    function blocks_of(severity) {
        return { Minor: 1, Moderate: 2, Severe: 3, Extreme: 4 }[severity] || 1;
    }

    function blocks_text(severity) {
        const n = root.blocks_of(severity);
        return n + (n === 1 ? " BLOCK" : " BLOCKS");
    }

    function scroll_detail(dir) {
        detail_flick.contentY = Math.max(0, Math.min(Math.max(0, detail_flick.contentHeight - detail_flick.height), detail_flick.contentY + dir * 40));
    }

    onAlert_cursorChanged: alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain)

    Rectangle {
        anchors.fill: parent
        visible: root.alerts.length === 0
        radius: 6
        color: Qt.alpha(Theme.bg_shadow, 0.35)
        border.width: 2
        border.color: Style.frame_border_color

        Text {
            anchors.centerIn: parent
            text: "NO SAVED DATA"
            color: Style.text_dim
            font.family: Style.font_family
            font.pixelSize: Style.fs(-1)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6
        visible: root.alerts.length > 0

        // At most three saves show; the rest scroll so the info panel keeps most of the height.
        MemCardPanel {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(3, root.alerts.length) * (root.row_h + alert_list.spacing) + chrome_h + alert_list.anchors.topMargin + 6
            heading: "MEMORY CARD  SLOT 1"
            trailing: root.alerts.length + (root.alerts.length === 1 ? " SAVE" : " SAVES")

            ListView {
                id: alert_list
                anchors.fill: parent
                anchors.topMargin: 2
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.alerts
                onCountChanged: Qt.callLater(() => alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain))

                delegate: Rectangle {
                    id: save
                    required property var modelData
                    required property int index
                    readonly property bool lit: save.index === root.alert_cursor
                    readonly property color severity_color: WeatherState.alert_color(save.modelData.severity)

                    width: ListView.view.width
                    height: root.row_h
                    radius: 4
                    color: save.lit ? Qt.alpha(Style.selection_bg, 0.55) : "transparent"
                    border.width: 2
                    border.color: save.lit ? Theme.theme_primary_light : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: root.row_h - 10
                            Layout.preferredHeight: root.row_h - 10
                            radius: 3
                            color: save.lit ? Style.selection_bg : Qt.alpha(Theme.bg_shadow, 0.45)
                            border.width: 2
                            border.color: save.lit ? Theme.theme_primary_light : Style.frame_border_color

                            Text {
                                anchors.centerIn: parent
                                text: "!"
                                color: save.severity_color
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(3)
                                font.bold: true
                                style: Text.Raised
                                styleColor: Style.text_shadow
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: save.modelData.event.toUpperCase()
                                color: save.lit ? Style.text_strong : Style.text_fg
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-2)
                            }

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: save.modelData.severity.toUpperCase() + (save.modelData.ends ? "  UNTIL " + root.fmt_time(save.modelData.ends).toUpperCase() : "")
                                color: save.lit ? Style.text_strong : Style.text_muted
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-5)
                            }
                        }

                        Text {
                            text: root.blocks_text(save.modelData.severity)
                            color: save.severity_color
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-5)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(save.index)
                    }
                }
            }
        }

        MemCardPanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            heading: "INFORMATION"
            trailing: root.selected ? root.blocks_text(root.selected.severity) : ""
            trailing_color: root.selected ? WeatherState.alert_color(root.selected.severity) : Style.text_strong

            Flickable {
                id: detail_flick
                anchors.fill: parent
                anchors.topMargin: 2
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
                        color: root.selected ? WeatherState.alert_color(root.selected.severity) : Style.text_fg
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size
                        font.bold: true
                    }

                    BlockGauge {
                        Layout.fillWidth: true
                        value: root.selected ? root.blocks_of(root.selected.severity) / root.severity_levels : 0
                        fill_color: root.selected ? WeatherState.alert_color(root.selected.severity) : Theme.theme_primary_light
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.selected ? root.fmt_time(root.selected.onset) + " – " + root.fmt_time(root.selected.ends) + "  ·  " + root.selected.area : ""
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-3)
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        wrapMode: Text.WordWrap
                        text: root.selected ? root.unwrap(root.selected.description) : ""
                        color: Style.text_fg
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        visible: !!root.selected && root.selected.instruction !== ""
                        wrapMode: Text.WordWrap
                        text: root.selected ? "What to do: " + root.unwrap(root.selected.instruction) : ""
                        color: Style.text_fg
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                    }
                }
            }
        }
    }
}
