import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.features.weather
import qs.styles.metroid.widgets
import qs.features.popups

// A Scan Visor logbook entry, "Threat": each active NWS alert as a scanned threat, the selected one locked on in brackets,
// its severity as a threat level and its text as the logbook entry. h/l or j/k select when there's more than one;
// with a single alert they scroll its detail text instead (see scroll_detail, called by the popup's key handler).
Item {
    id: root

    property int alert_cursor: 0
    // Called with the clicked alert index; the popup owns alert_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real detail_y: 0
    property var on_detail_scroll: function (y) {}

    readonly property color visor: Theme.theme_label
    readonly property color visor_light: Style.pal.fg_strong
    readonly property bool shown: root.visible && Popups.open_name === "weather"

    readonly property var alerts: WeatherState.alerts
    readonly property var selected: root.alerts[Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor))]

    readonly property var weekday_names: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property var threat_levels: ({ Extreme: 4, Severe: 3, Moderate: 2, Minor: 1 })
    readonly property int level_pips: 4

    function threat_level(severity) {
        return root.threat_levels[severity] || 0;
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

    readonly property int row_h: Style.px(38)

    onAlert_cursorChanged: alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain)

    // Threat level as filled and empty pips in the severity's colour.
    component LevelPips: Row {
        id: pips
        property int level: 0
        property color tone: root.visor
        spacing: 2

        Repeater {
            model: root.level_pips

            Rectangle {
                required property int index
                width: 8
                height: 4
                color: index < pips.level ? pips.tone : Qt.alpha(pips.tone, 0.18)
            }
        }
    }

    component SectionLabel: Text {
        Layout.fillWidth: true
        Layout.topMargin: 4
        color: root.visor
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.letterSpacing: 2.5
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "LOGBOOK"
                color: root.visor
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 2.5
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.alerts.length > 0 ? "THREAT" : "NO THREATS DETECTED"
                color: Style.pal.fg_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 2.5
            }

            Text {
                visible: root.alerts.length > 0
                text: root.alerts.length + (root.alerts.length === 1 ? " SIGNATURE" : " SIGNATURES")
                color: root.visor
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 1.5

                SequentialAnimation on opacity {
                    running: root.shown && root.alerts.length > 0
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.4; duration: 800; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.4; to: 1; duration: 800; easing.type: Easing.InOutSine }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: -4
            Layout.preferredHeight: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.alpha(root.visor, 0.6) }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        // At most three rows show; the rest scroll so the detail keeps most of the height.
        ListView {
            id: alert_list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(3, root.alerts.length) * (root.row_h + spacing)
            visible: root.alerts.length > 0
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: root.alerts
            onCountChanged: Qt.callLater(() => alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain))

            delegate: Item {
                id: threat_row
                required property var modelData
                required property int index
                readonly property bool open: threat_row.index === root.alert_cursor
                readonly property color tone: WeatherState.alert_color(threat_row.modelData.severity)

                width: ListView.view.width
                height: root.row_h

                Rectangle {
                    anchors.fill: parent
                    color: Qt.alpha(threat_row.tone, threat_row.open ? 0.1 : 0.03)
                }

                ScanLock {
                    visible: threat_row.open
                    shown: threat_row.open && root.shown
                    color: threat_row.tone
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: threat_row.modelData.event.toUpperCase()
                            color: threat_row.open ? Style.pal.fg_strong : Style.pal.fg
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-2)
                            font.letterSpacing: 0.8
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: threat_row.modelData.ends ? "UNTIL " + root.fmt_time(threat_row.modelData.ends).toUpperCase() : "NO END TIME"
                            color: Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-5)
                            font.letterSpacing: 1.2
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 3

                        LevelPips {
                            Layout.alignment: Qt.AlignRight
                            level: root.threat_level(threat_row.modelData.severity)
                            tone: threat_row.tone
                        }

                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: threat_row.modelData.severity.toUpperCase()
                            color: threat_row.tone
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-5)
                            font.letterSpacing: 1.5
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.on_select(threat_row.index)
                }
            }
        }

        Item {
            Layout.fillHeight: true
            visible: !root.selected
        }

        Flickable {
            id: detail_flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: detail_col.implicitHeight
            visible: !!root.selected
            boundsBehavior: Flickable.StopAtBounds
            onContentYChanged: root.on_detail_scroll(detail_flick.contentY)
            Component.onCompleted: detail_flick.contentY = root.detail_y

            ColumnLayout {
                id: detail_col
                width: detail_flick.width
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "THREAT LEVEL"
                        color: root.visor
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-5)
                        font.letterSpacing: 2
                    }

                    LevelPips {
                        level: root.selected ? root.threat_level(root.selected.severity) : 0
                        tone: root.selected ? WeatherState.alert_color(root.selected.severity) : root.visor
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.selected ? root.selected.severity.toUpperCase() : ""
                        color: root.selected ? WeatherState.alert_color(root.selected.severity) : Style.pal.fg
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-4)
                        font.letterSpacing: 1.5
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    wrapMode: Text.WordWrap
                    text: root.selected ? root.selected.headline || root.selected.event : ""
                    color: root.selected ? WeatherState.alert_color(root.selected.severity) : Style.pal.fg
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.selected ? root.fmt_time(root.selected.onset) + " – " + root.fmt_time(root.selected.ends) + "  ·  " + root.selected.area : ""
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.preferredHeight: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.alpha(root.visor, 0.4) }
                        GradientStop { position: 1; color: Qt.alpha(root.visor, 0.05) }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    wrapMode: Text.WordWrap
                    text: root.selected ? root.unwrap(root.selected.description) : ""
                    color: Style.pal.fg
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-2)
                }

                SectionLabel {
                    visible: !!root.selected && root.selected.instruction !== ""
                    text: "COUNTERMEASURES"
                }

                Text {
                    Layout.fillWidth: true
                    visible: !!root.selected && root.selected.instruction !== ""
                    wrapMode: Text.WordWrap
                    text: root.selected ? root.unwrap(root.selected.instruction) : ""
                    color: Style.pal.fg
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-2)
                }
            }
        }
    }
}
