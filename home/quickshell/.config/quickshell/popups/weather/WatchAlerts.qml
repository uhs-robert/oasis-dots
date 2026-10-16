import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.lock.skins.goldeneye as Watch
import "../../theme/Watch.js" as W

// The Alerts tab as a GoldenEye mission briefing on the pause watch: each alert an objective, the selected one briefed in full by M with its priority (severity),
// the time left on the LCD digits, the description as the briefing and the instruction as orders. h/l or j/k select when there's more than one;
// with a single alert they scroll its briefing instead (see scroll_detail, called by the popup's key handler).
Item {
    id: root

    property int alert_cursor: 0
    // Called with the clicked alert index; the popup owns alert_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real detail_y: 0
    property var on_detail_scroll: function (y) {}

    readonly property var alerts: WeatherState.alerts
    readonly property var selected: root.alerts[Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor))]
    readonly property int row_h: Style.px(40)
    property real now_ms: Date.now()

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

    // Hours and minutes until the alert ends, for the LCD digits; "--:--" when it has no end.
    function time_left(iso) {
        if (!iso) return "--:--";
        const mins = Math.max(0, Math.floor((new Date(iso).getTime() - root.now_ms) / 60000));
        return Math.floor(mins / 60) + ":" + String(mins % 60).padStart(2, "0");
    }

    onAlert_cursorChanged: alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain)

    Timer {
        interval: 30000
        repeat: true
        running: Popups.open_name === "weather" && root.visible
        onTriggered: root.now_ms = Date.now()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "MISSION BRIEFING"
                color: W.red
                font.family: W.head_font
                font.pixelSize: Style.fs(-4)
                font.letterSpacing: 2
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Qt.alpha(W.red, 0.5)
            }

            Text {
                text: root.alerts.length === 0 ? "NO OBJECTIVES" : root.alerts.length + (root.alerts.length === 1 ? " OBJECTIVE" : " OBJECTIVES")
                color: Style.wk.mid
                font.family: W.mono_font
                font.pixelSize: Style.fs(-4)
                font.letterSpacing: 1
            }
        }

        Text {
            visible: root.alerts.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            verticalAlignment: Text.AlignTop
            text: "NO ACTIVE ALERTS"
            color: Style.wk.dim
            font.family: W.mono_font
            font.pixelSize: Style.fs(-1)
            font.letterSpacing: 1
        }

        // At most three rows show; the rest scroll so the briefing keeps most of the height.
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

            delegate: Item {
                id: objective
                required property var modelData
                required property int index
                readonly property bool at_cursor: objective.index === root.alert_cursor
                readonly property color severity_color: WeatherState.alert_color(objective.modelData.severity)

                width: ListView.view.width
                height: root.row_h

                Watch.PanelShape {
                    visible: objective.at_cursor
                    anchors.fill: parent
                    cut: 6
                    notches: false
                    top_color: Style.wk.panel_top
                    bottom_color: Style.wk.panel_bottom
                    edge: Style.wk.edge
                }

                Rectangle {
                    visible: objective.at_cursor
                    x: 0
                    y: 8
                    width: 3
                    height: parent.height - 16
                    color: W.red
                }

                Text {
                    id: number
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    text: objective.index + 1
                    color: objective.at_cursor ? Style.wk.lit : Style.wk.dim
                    font.family: W.digit_font
                    font.pixelSize: Style.fs(4)
                }

                ColumnLayout {
                    anchors.left: number.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: objective.modelData.event.toUpperCase()
                        color: W.red
                        opacity: objective.at_cursor ? 1 : 0.7
                        font.family: W.mono_font
                        font.pixelSize: Style.fs(-1)
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "PRIORITY: " + objective.modelData.severity.toUpperCase() + (objective.modelData.ends ? " · UNTIL " + root.fmt_time(objective.modelData.ends).toUpperCase() : "")
                        color: objective.at_cursor ? Style.wk.mid : Style.wk.dim
                        font.family: W.mono_font
                        font.pixelSize: Style.fs(-4)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.on_select(objective.index)
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !!root.selected

            Watch.PanelShape {
                anchors.fill: parent
                cut: 8
                notches: false
                top_color: Style.wk.panel_top
                bottom_color: Style.wk.panel_bottom
                edge: Style.wk.edge
            }

            RowLayout {
                id: brief_head
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                anchors.topMargin: 8
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: "PRIORITY"
                        color: Style.wk.dim
                        font.family: W.mono_font
                        font.pixelSize: Style.fs(-5)
                        font.letterSpacing: 2
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.selected ? root.selected.severity.toUpperCase() : ""
                        color: root.selected ? WeatherState.alert_color(root.selected.severity) : Style.wk.dim
                        font.family: W.head_font
                        font.pixelSize: Style.fs(0)
                        font.letterSpacing: 1
                    }
                }

                ColumnLayout {
                    spacing: 0

                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: "TIME LEFT"
                        color: Style.wk.dim
                        font.family: W.mono_font
                        font.pixelSize: Style.fs(-5)
                        font.letterSpacing: 2
                    }

                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: root.selected ? root.time_left(root.selected.ends) : ""
                        color: Style.wk.lit
                        font.family: W.digit_font
                        font.pixelSize: Style.fs(6)
                    }
                }
            }

            Rectangle {
                id: brief_rule
                anchors.top: brief_head.bottom
                anchors.topMargin: 6
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                height: 1
                color: Style.wk.edge
            }

            Flickable {
                id: detail_flick
                anchors.top: brief_rule.bottom
                anchors.topMargin: 6
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 16
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
                        color: Style.wk.lit
                        font.family: W.mono_font
                        font.pixelSize: Style.fs(-2)
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.selected ? root.fmt_time(root.selected.onset).toUpperCase() + " – " + root.fmt_time(root.selected.ends).toUpperCase() + "  ·  " + root.selected.area : ""
                        color: Style.wk.mid
                        font.family: W.mono_font
                        font.pixelSize: Style.fs(-4)
                    }

                    Text {
                        Layout.topMargin: 6
                        text: "BRIEFING"
                        color: W.red
                        font.family: W.head_font
                        font.pixelSize: Style.fs(-5)
                        font.letterSpacing: 2
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.selected ? root.unwrap(root.selected.description) : ""
                        color: Style.wk.soft
                        font.family: W.mono_font
                        font.pixelSize: Style.fs(-3)
                    }

                    Text {
                        visible: !!root.selected && root.selected.instruction !== ""
                        Layout.topMargin: 6
                        text: "ORDERS"
                        color: W.red
                        font.family: W.head_font
                        font.pixelSize: Style.fs(-5)
                        font.letterSpacing: 2
                    }

                    Text {
                        visible: !!root.selected && root.selected.instruction !== ""
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.selected ? root.unwrap(root.selected.instruction) : ""
                        color: Style.wk.lit
                        font.family: W.mono_font
                        font.pixelSize: Style.fs(-3)
                    }
                }
            }

            Rectangle {
                visible: detail_flick.contentHeight > detail_flick.height
                x: parent.width - 9
                y: detail_flick.y + detail_flick.height * (detail_flick.contentY / detail_flick.contentHeight)
                width: 3
                height: Math.max(12, detail_flick.height * detail_flick.height / detail_flick.contentHeight)
                color: Style.wk.mid
                opacity: 0.7
            }
        }
    }
}
