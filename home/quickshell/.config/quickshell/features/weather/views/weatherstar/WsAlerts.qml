import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.features.weather
import qs.styles.crt.widgets
import qs.features.popups

// WeatherStar 4000 warning page: a red banner with the selected alert's event in large letters, the statement text on a blue panel,
// and a red crawl of every alert headline along the bottom. With several alerts a list picks one (h/l, j/k);
// with a single alert h/l scroll the statement instead (see scroll_detail, called by the popup's key handler).
Item {
    id: root

    property int alert_cursor: 0
    // Called with the clicked alert index; the popup owns alert_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real detail_y: 0
    property var on_detail_scroll: function (y) {}

    readonly property var alerts: WeatherState.alerts
    readonly property var selected: root.alerts[Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor))]
    readonly property bool popup_open: root.visible && Popups.open_name === "weather"

    readonly property color warn_top: Qt.hsla(Style.pal.error.hslHue, 0.85, 0.34, 1)
    readonly property color warn_bottom: Qt.hsla(Style.pal.error.hslHue, 0.85, 0.2, 1)

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

    readonly property int row_h: Style.px(30)

    onAlert_cursorChanged: alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain)

    component Label: Text {
        color: Theme.fg_strong
        font.family: Style.font_family
        font.pixelSize: Style.fs(-3)
        style: Text.Outline
        styleColor: Theme.bg_shadow
    }

    component RedBand: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0; color: root.warn_top }
            GradientStop { position: 1; color: root.warn_bottom }
        }
        border.width: 2
        border.color: Qt.alpha(Style.pal.bright_red, 0.6)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        Label {
            visible: root.alerts.length === 0
            text: "No active alerts"
            color: Style.text_dim
            font.pixelSize: Style.fs(-1)
        }

        RedBand {
            visible: root.alerts.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: banner.implicitHeight + 12

            ColumnLayout {
                id: banner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 8
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        text: "Local Statement"
                        color: Theme.theme_secondary
                    }

                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        text: root.selected ? root.selected.severity + (root.alerts.length > 1 ? " · " + (root.alert_cursor + 1) + " of " + root.alerts.length : "") : ""
                    }
                }

                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.selected ? root.selected.event.toUpperCase() : ""
                    font.pixelSize: Style.fs(3)
                    font.bold: true
                }
            }
        }

        // At most three rows show; the rest scroll so the statement keeps most of the height.
        ListView {
            id: alert_list
            Layout.fillWidth: true
            Layout.preferredHeight: root.alerts.length > 1 ? Math.min(3, root.alerts.length) * (root.row_h + spacing) - spacing : 0
            visible: root.alerts.length > 1
            clip: true
            spacing: 3
            boundsBehavior: Flickable.StopAtBounds
            model: root.alerts
            onCountChanged: Qt.callLater(() => alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain))

            delegate: Item {
                id: alert_row
                required property var modelData
                required property int index
                readonly property bool current: alert_row.index === root.alert_cursor

                width: ListView.view.width
                height: root.row_h

                WsPanel {
                    anchors.fill: parent
                    anchors.margins: alert_row.current ? 2 : 0
                    lit: alert_row.current
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        color: WeatherState.alert_color(alert_row.modelData.severity)
                        border.width: 1
                        border.color: Theme.bg_shadow
                    }

                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: alert_row.modelData.event
                        color: alert_row.current ? Theme.theme_secondary : Theme.fg_strong
                        font.pixelSize: Style.fs(-2)
                    }

                    Label {
                        Layout.maximumWidth: parent.width * 0.4
                        elide: Text.ElideRight
                        text: alert_row.modelData.ends ? "Until " + root.fmt_time(alert_row.modelData.ends) : alert_row.modelData.severity
                        color: Theme.theme_primary_light
                        font.pixelSize: Style.fs(-4)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.on_select(alert_row.index)
                }
            }
        }

        Item {
            visible: !!root.selected
            Layout.fillWidth: true
            Layout.fillHeight: true

            WsPanel {
                anchors.fill: parent
            }

            Flickable {
                id: detail_flick
                anchors.fill: parent
                anchors.margins: 8
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

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.selected ? root.selected.headline || root.selected.event : ""
                        color: root.selected ? WeatherState.alert_color(root.selected.severity) : Theme.fg_strong
                        font.pixelSize: Style.fs(-2)
                        font.bold: true
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.selected ? root.fmt_time(root.selected.onset) + " – " + root.fmt_time(root.selected.ends) + "  ·  " + root.selected.area : ""
                        color: Theme.theme_primary_light
                        font.pixelSize: Style.fs(-4)
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        wrapMode: Text.WordWrap
                        text: root.selected ? root.unwrap(root.selected.description) : ""
                        font.pixelSize: Style.fs(-3)
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        visible: !!root.selected && root.selected.instruction !== ""
                        wrapMode: Text.WordWrap
                        text: root.selected ? "What to do: " + root.unwrap(root.selected.instruction) : ""
                        font.pixelSize: Style.fs(-3)
                    }
                }
            }
        }

        RedBand {
            id: crawl
            visible: root.alerts.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: crawl_a.implicitHeight + 8
            clip: true

            readonly property string headlines: root.alerts.map(a => a.headline || a.event).join("   ***   ") + "   ***   "
            // A headline shorter than the bar still scrolls fully across before it repeats.
            readonly property real period: Math.max(crawl_a.implicitWidth, crawl.width)

            Label {
                id: crawl_a
                y: 4
                x: crawl_run.x_off
                text: crawl.headlines
                font.pixelSize: Style.fs(-3)
            }

            Label {
                y: 4
                x: crawl_a.x + crawl.period
                text: crawl.headlines
                font.pixelSize: Style.fs(-3)
            }

            QtObject {
                id: crawl_run
                property real x_off: 0
            }

            NumberAnimation {
                target: crawl_run
                property: "x_off"
                from: 0
                to: -crawl.period
                duration: Math.max(1000, crawl.period * 22)
                loops: Animation.Infinite
                running: root.popup_open && root.alerts.length > 0 && crawl.period > 0
            }
        }
    }
}
