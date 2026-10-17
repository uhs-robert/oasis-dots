pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.ui.effects
import qs.ui.menu
import qs.theme
import qs.services
import qs.ui.gauges

// Active NWS alerts as an FF7 battle: the selected alert's event in the battle-message bar, the alerts as an enemy
// list under the white glove, and the selected one as a Sense window. With a single alert, h/l scroll its detail
// instead (see scroll_detail, called by the popup's key handler).
Item {
    id: root

    property int alert_cursor: 0
    // Called with the clicked alert index; the popup owns alert_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real detail_y: 0
    property var on_detail_scroll: function (y) {}

    readonly property var alerts: WeatherState.alerts
    readonly property var selected: root.alerts[Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor))]
    readonly property color selected_color: root.selected ? WeatherState.alert_color(root.selected.severity) : Style.text_dim

    readonly property var weekday_names: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property var severity_levels: ({ Extreme: 4, Severe: 3, Moderate: 2, Minor: 1 })
    readonly property int row_h: Style.px(34)

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

    function level_of(alert) {
        return root.severity_levels[alert.severity] || 0;
    }

    function level_text(alert) {
        return "LV " + (root.level_of(alert) || "?");
    }

    function scroll_detail(dir) {
        detail_flick.contentY = Math.max(0, Math.min(Math.max(0, detail_flick.contentHeight - detail_flick.height), detail_flick.contentY + dir * 40));
    }

    onAlert_cursorChanged: alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain)

    component Label: Text {
        color: Theme.theme_primary_light
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
        font.weight: Font.ExtraBold
        font.letterSpacing: 1
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        Item {
            visible: root.alerts.length === 0
            Layout.fillWidth: true
            Layout.preferredHeight: 34

            StatusWindow {
                anchors.fill: parent
            }

            Text {
                anchors.centerIn: parent
                text: "No active alerts"
                color: Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
            }
        }

        // The battle-message bar.
        Item {
            visible: !!root.selected
            Layout.fillWidth: true
            Layout.preferredHeight: message_body.implicitHeight + 14

            StatusWindow {
                anchors.fill: parent
            }

            RowLayout {
                id: message_body
                anchors.fill: parent
                anchors.margins: 7
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 7

                MateriaOrb {
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14
                    color: root.selected_color
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: root.selected ? root.selected.event : ""
                    color: Qt.tint(Theme.fg_strong, Qt.alpha(root.selected_color, 0.35))
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(1)
                    font.weight: Font.ExtraBold
                }

                Label {
                    visible: root.alerts.length > 1
                    text: (root.alert_cursor + 1) + "/" + root.alerts.length
                }
            }
        }

        // The enemy list: at most three rows show, the rest scroll so the Sense window keeps most of the height.
        Item {
            visible: root.alerts.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(3, root.alerts.length) * (root.row_h + alert_list.spacing) - alert_list.spacing + 12

            StatusWindow {
                anchors.fill: parent
            }

            ListView {
                id: alert_list
                anchors.fill: parent
                anchors.margins: 6
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.alerts
                onCountChanged: Qt.callLater(() => alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain))

                delegate: MenuRow {
                    id: alert_row
                    required property var modelData
                    required property int index
                    readonly property color tint: WeatherState.alert_color(alert_row.modelData.severity)

                    width: ListView.view.width
                    height: root.row_h
                    selected: alert_row.index === root.alert_cursor

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        anchors.leftMargin: 4 + alert_row.inset
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: alert_row.modelData.event
                            color: alert_row.selected ? Theme.fg_strong : Theme.theme_primary_light
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-1)
                            font.weight: Font.ExtraBold
                        }

                        ColumnLayout {
                            Layout.preferredWidth: Math.max(54, parent.width * 0.22)
                            spacing: 2

                            Label {
                                Layout.alignment: Qt.AlignRight
                                text: root.level_text(alert_row.modelData)
                                color: alert_row.tint
                            }

                            AtbBar {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 5
                                value: root.level_of(alert_row.modelData) / 4
                                fill_color: alert_row.tint
                                shade_color: Qt.tint(alert_row.tint, Qt.alpha(Theme.fg_strong, 0.5))
                                horizontal: true
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(alert_row.index)
                    }
                }
            }
        }

        // The Sense window: the stats stay put, the prose scrolls.
        Item {
            visible: !!root.selected
            Layout.fillWidth: true
            Layout.fillHeight: true

            StatusWindow {
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                anchors.leftMargin: 11
                anchors.rightMargin: 11
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    MateriaOrb {
                        Layout.preferredWidth: 11
                        Layout.preferredHeight: 11
                        color: root.selected_color
                    }

                    Label {
                        text: "SENSE"
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Label {
                        text: root.selected ? root.level_text(root.selected) : ""
                        color: root.selected_color
                    }

                    Text {
                        text: root.selected ? root.selected.severity : ""
                        color: Theme.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                        font.weight: Font.ExtraBold
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 1

                    Label { text: "FROM" }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.selected ? root.fmt_time(root.selected.onset) : ""
                        color: Theme.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                        font.weight: Font.ExtraBold
                    }

                    Label { text: "UNTIL" }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.selected ? root.fmt_time(root.selected.ends) : ""
                        color: Theme.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                        font.weight: Font.ExtraBold
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
                            wrapMode: Text.WordWrap
                            text: root.selected ? root.selected.headline || root.selected.event : ""
                            color: root.selected_color
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size
                            font.weight: Font.ExtraBold
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: root.selected ? root.selected.area : ""
                            color: Theme.theme_primary_light
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-3)
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            wrapMode: Text.WordWrap
                            text: root.selected ? root.unwrap(root.selected.description) : ""
                            color: Theme.fg_strong
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-2)
                        }

                        Label {
                            Layout.topMargin: 4
                            visible: !!root.selected && root.selected.instruction !== ""
                            text: "WHAT TO DO"
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !!root.selected && root.selected.instruction !== ""
                            wrapMode: Text.WordWrap
                            text: root.selected ? root.unwrap(root.selected.instruction) : ""
                            color: Theme.fg_strong
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-2)
                        }
                    }
                }
            }
        }
    }
}
