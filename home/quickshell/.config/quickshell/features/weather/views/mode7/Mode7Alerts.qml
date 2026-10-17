import QtQuick
import QtQuick.Layouts
import qs.ui.effects
import qs.ui.menu
import qs.styles.snes.widgets as Snes
import qs.theme
import qs.services
import qs.features.weather

// Active NWS alerts as an RPG event: an item-menu window lists the alerts with the glove on the selected one and severity as a star rating,
// and a dialogue window under it speaks the selected alert, the event as the speaker, a blinking ▼ while more text waits.
// h/l or j/k select when there's more than one; with a single alert they scroll its text instead (see scroll_detail, called by the popup's key handler).
Item {
    id: root

    property int alert_cursor: 0
    // Called with the clicked alert index; the popup owns alert_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real detail_y: 0
    property var on_detail_scroll: function (y) {}

    readonly property var alerts: WeatherState.alerts
    readonly property var selected: root.alerts[Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor))]
    readonly property bool scene_live: root.visible && Popups.open_name === "weather"
    readonly property real max_scroll: Math.max(0, detail_flick.contentHeight - detail_flick.height)

    readonly property var weekday_names: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property int row_h: 34
    readonly property int max_rows: 3
    readonly property int star_count: 4

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

    // NWS severity as the number of lit stars.
    function stars_of(severity) {
        return ({ Extreme: 4, Severe: 3, Moderate: 2, Minor: 1 })[severity] || 0;
    }

    function scroll_detail(dir) {
        detail_flick.contentY = Math.max(0, Math.min(root.max_scroll, detail_flick.contentY + dir * 40));
    }

    onAlert_cursorChanged: alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain)

    Text {
        visible: root.alerts.length === 0
        anchors.centerIn: parent
        text: "NO ACTIVE ALERTS"
        color: Style.text_dim
        font.family: Style.font_family
        font.pixelSize: Style.font_size
        style: Text.Raised
        styleColor: Style.text_shadow
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        visible: root.alerts.length > 0

        Snes.SnesWindow {
            id: menu_window
            Layout.fillWidth: true
            lit: true
            implicitHeight: Math.min(root.max_rows, root.alerts.length) * (root.row_h + alert_list.spacing) - alert_list.spacing + 16 + drop

            ListView {
                id: alert_list
                anchors.fill: menu_window.panel
                anchors.margins: 8
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.alerts
                onCountChanged: Qt.callLater(() => alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain))

                delegate: Item {
                    id: alert_row
                    required property var modelData
                    required property int index
                    readonly property bool selected: alert_row.index === root.alert_cursor
                    readonly property color tone: WeatherState.alert_color(alert_row.modelData.severity)

                    width: ListView.view.width
                    height: root.row_h

                    HandCursor {
                        visible: alert_row.selected
                        x: 0
                        y: Math.round((alert_row.height - height) / 2)
                        width: 19
                        height: 12
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 24
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: alert_row.modelData.event.toUpperCase()
                                color: alert_row.selected ? Style.pal.secondary : Style.pal.fg_strong
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-1)
                                style: Text.Raised
                                styleColor: Style.text_shadow
                            }

                            Row {
                                spacing: 2
                                Repeater {
                                    model: root.star_count

                                    PixelSprite {
                                        required property int index
                                        readonly property bool lit: index < root.stars_of(alert_row.modelData.severity)
                                        pixel: 2
                                        colors: [Style.pal.bg_crust, lit ? alert_row.tone : Style.pal.fg_dim]
                                        rows: ["..1..", ".111.", "11111", ".111.", "11.11", "1...1"]
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: (alert_row.modelData.severity + (alert_row.modelData.ends ? " · until " + root.fmt_time(alert_row.modelData.ends) : "")).toUpperCase()
                            color: Style.pal.primary_light
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-8)
                            style: Text.Raised
                            styleColor: Style.text_shadow
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(alert_row.index)
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !!root.selected

            Snes.SnesWindow {
                id: dialogue_window
                anchors.fill: parent
                anchors.topMargin: speaker_tab.height / 2
            }

            Snes.SnesWindow {
                id: speaker_tab
                x: 14
                width: Math.min(parent.width - 28 - drop, speaker.implicitWidth + 24 + drop)
                height: speaker.implicitHeight + 12 + drop
                top_color: dialogue_window.top_color
                bottom_color: dialogue_window.top_color

                Text {
                    id: speaker
                    anchors.centerIn: speaker_tab.panel
                    width: speaker_tab.panel.width - 16
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: root.selected ? root.selected.event.toUpperCase() : ""
                    color: root.selected ? WeatherState.alert_color(root.selected.severity) : Style.pal.fg
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-1)
                    style: Text.Raised
                    styleColor: Style.text_shadow
                }
            }

            Flickable {
                id: detail_flick
                anchors.fill: dialogue_window
                anchors.topMargin: speaker_tab.height / 2 + 8
                anchors.leftMargin: 14
                anchors.rightMargin: 14 + dialogue_window.drop
                anchors.bottomMargin: 20 + dialogue_window.drop
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
                        color: Style.pal.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-1)
                        font.bold: true
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.selected ? root.fmt_time(root.selected.onset) + " – " + root.fmt_time(root.selected.ends) + "  ·  " + root.selected.area : ""
                        color: Style.pal.primary_light
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-3)
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        wrapMode: Text.WordWrap
                        text: root.selected ? root.unwrap(root.selected.description) : ""
                        color: Style.pal.fg
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                        style: Text.Raised
                        styleColor: Style.text_shadow
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
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }
                }
            }

            // The page-turn prompt: ▼ while text waits below, ▲ while text is scrolled above.
            Text {
                id: more_below
                readonly property bool waiting: root.max_scroll - detail_flick.contentY > 1
                property bool shown: true
                visible: more_below.waiting && more_below.shown
                anchors.right: dialogue_window.right
                anchors.bottom: dialogue_window.bottom
                anchors.rightMargin: 10 + dialogue_window.drop
                anchors.bottomMargin: 6 + dialogue_window.drop
                text: "▼"
                color: Style.pal.fg_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)

                Timer {
                    interval: 450
                    repeat: true
                    running: root.scene_live && more_below.waiting
                    onRunningChanged: if (!running) more_below.shown = true
                    onTriggered: more_below.shown = !more_below.shown
                }
            }

            Text {
                visible: detail_flick.contentY > 1
                anchors.right: dialogue_window.right
                anchors.top: dialogue_window.top
                anchors.rightMargin: 10 + dialogue_window.drop
                anchors.topMargin: 6
                text: "▲"
                color: Style.pal.primary_light
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }
        }
    }
}
