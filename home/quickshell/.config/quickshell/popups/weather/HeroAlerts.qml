// home/quickshell/.config/quickshell/popups/weather/HeroAlerts.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// Modern Alerts: a stack of notification cards tinted by severity, with the selected alert expanded below
// into its time chips and readable paragraphs. With a single alert h/l scroll the detail (see scroll_detail).
Item {
    id: root

    property int alert_cursor: 0
    // Called with the clicked alert index; the popup owns alert_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real detail_y: 0
    property var on_detail_scroll: function (y) {}

    readonly property var alerts: WeatherState.alerts
    readonly property var selected: root.alerts[Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor))]
    readonly property color accent: root.selected ? WeatherState.alert_color(root.selected.severity) : Style.text_dim

    readonly property var weekday_names: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property real card_h: Style.px(46)

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

    function paragraphs(text) {
        return root.unwrap(text).split(/\n\s*\n/).map(p => p.trim()).filter(p => p !== "");
    }

    function scroll_detail(dir) {
        detail_flick.contentY = Math.max(0, Math.min(Math.max(0, detail_flick.contentHeight - detail_flick.height), detail_flick.contentY + dir * 40));
    }

    onAlert_cursorChanged: alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain)

    component Chip: Rectangle {
        id: chip
        property string label: ""
        property string caption: ""
        property color tone: Style.text_muted

        implicitWidth: chip_row.implicitWidth + 16
        implicitHeight: chip_row.implicitHeight + 6
        radius: height / 2
        color: Qt.alpha(chip.tone, 0.14)

        Row {
            id: chip_row
            anchors.centerIn: parent
            spacing: 5

            Text {
                visible: chip.caption !== ""
                text: chip.caption
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4
            }

            Text {
                text: chip.label
                color: chip.tone
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
                font.weight: Font.DemiBold
            }
        }
    }

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
        spacing: 8
        visible: root.alerts.length > 0

        // At most two cards show above the detail; the rest scroll so the detail keeps most of the height.
        ListView {
            id: alert_list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(2, root.alerts.length) * (root.card_h + spacing) - spacing
            visible: root.alerts.length > 1
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: root.alerts
            onCountChanged: Qt.callLater(() => alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain))

            delegate: Item {
                id: card
                required property var modelData
                required property int index
                readonly property bool is_selected: card.index === root.alert_cursor
                readonly property color tone: WeatherState.alert_color(card.modelData.severity)

                width: ListView.view.width
                height: root.card_h

                Rectangle {
                    anchors.fill: parent
                    radius: Style.radius(10)
                    border.width: 1
                    border.color: card.is_selected ? Qt.alpha(card.tone, 0.7) : Style.frame_border_color
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.alpha(card.tone, card.is_selected ? 0.3 : 0.1) }
                        GradientStop { position: 1; color: Qt.alpha(card.tone, card.is_selected ? 0.14 : 0.04) }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        radius: 13
                        color: Qt.alpha(card.tone, 0.22)

                        Text {
                            anchors.centerIn: parent
                            text: "!"
                            color: card.tone
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(1)
                            font.weight: Font.Bold
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: card.modelData.event
                            color: Style.text_strong
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-1)
                            font.weight: card.is_selected ? Font.Bold : Font.DemiBold
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: card.modelData.severity + (card.modelData.ends ? "  ·  until " + root.fmt_time(card.modelData.ends) : "")
                            color: Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-3)
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.on_select(card.index)
                }
            }
        }

        Rectangle {
            id: detail_card
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !!root.selected
            radius: Style.radius(12)
            // Solid so the scroll fades can blend into it exactly.
            color: Qt.tint(Style.frame_color, Qt.alpha(root.accent, 0.1))
            border.width: 1
            border.color: Qt.alpha(root.accent, 0.45)

            Rectangle {
                x: 7
                y: 14
                width: 3
                height: parent.height - 28
                radius: 1.5
                color: root.accent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 12
                anchors.topMargin: 10
                anchors.bottomMargin: 0
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.selected ? root.selected.event : ""
                    color: Style.text_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(1)
                    font.weight: Font.Bold
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Chip { label: root.selected ? root.selected.severity : ""; tone: root.accent }
                    Chip { caption: "FROM"; label: root.selected ? root.fmt_time(root.selected.onset) : "" }
                    Chip { caption: "UNTIL"; label: root.selected ? root.fmt_time(root.selected.ends) : "" }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Flickable {
                        id: detail_flick
                        anchors.fill: parent
                        clip: true
                        contentWidth: width
                        contentHeight: detail_col.implicitHeight + 16
                        boundsBehavior: Flickable.StopAtBounds
                        onContentYChanged: root.on_detail_scroll(detail_flick.contentY)
                        Component.onCompleted: detail_flick.contentY = root.detail_y

                        ColumnLayout {
                            id: detail_col
                            width: detail_flick.width
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                wrapMode: Text.WordWrap
                                text: root.selected ? root.selected.headline : ""
                                color: root.accent
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-1)
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                wrapMode: Text.Wrap
                                text: root.selected ? root.selected.area : ""
                                color: Style.text_muted
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-3)
                            }

                            Repeater {
                                model: root.selected ? root.paragraphs(root.selected.description) : []

                                Text {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.15
                                    text: modelData
                                    color: Style.pal.fg
                                    font.family: Style.font_family
                                    font.pixelSize: Style.fs(-2)
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                visible: !!root.selected && root.selected.instruction !== ""
                                radius: Style.radius(8)
                                color: Qt.alpha(root.accent, 0.12)
                                implicitHeight: todo_col.implicitHeight + 16

                                ColumnLayout {
                                    id: todo_col
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 4

                                    Text {
                                        text: "WHAT TO DO"
                                        color: root.accent
                                        font.family: Style.font_family
                                        font.pixelSize: Style.fs(-4)
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.8
                                    }

                                    Repeater {
                                        model: root.selected ? root.paragraphs(root.selected.instruction) : []

                                        Text {
                                            required property string modelData
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            lineHeight: 1.15
                                            text: modelData
                                            color: Style.pal.fg
                                            font.family: Style.font_family
                                            font.pixelSize: Style.fs(-2)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 18
                        opacity: detail_flick.contentY > 1 ? 1 : 0
                        gradient: Gradient {
                            GradientStop { position: 0; color: detail_card.color }
                            GradientStop { position: 1; color: Qt.alpha(detail_card.color, 0) }
                        }
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 26
                        opacity: detail_flick.contentY < detail_flick.contentHeight - detail_flick.height - 1 ? 1 : 0
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.alpha(detail_card.color, 0) }
                            GradientStop { position: 1; color: detail_card.color }
                        }
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                }
            }
        }
    }
}
