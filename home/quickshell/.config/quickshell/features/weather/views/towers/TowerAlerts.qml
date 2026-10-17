import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.features.weather

// Active NWS alerts as PS2 system-dialog glass: one card per alert with a soft glow in its severity colour,
// the selected alert's full text in a translucent panel below. h/l or j/k select when there's more than one;
// with a single alert they scroll its detail text instead (see scroll_detail, called by the popup's key handler).
Item {
    id: root

    property int alert_cursor: 0
    // Called with the clicked alert index; the popup owns alert_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real detail_y: 0
    property var on_detail_scroll: function (y) {}

    readonly property var alerts: WeatherState.alerts
    readonly property var selected: root.alerts[Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor))]
    readonly property color selected_color: root.selected ? WeatherState.alert_color(root.selected.severity) : Theme.theme_primary_light

    readonly property var weekday_names: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property int card_h: Style.px(44)

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

    component Caption: Text {
        color: Theme.theme_primary_light
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.2
        elide: Text.ElideRight
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Caption {
            Layout.fillWidth: true
            text: "Weather alerts" + (root.alerts.length > 1 ? " · " + root.alerts.length : "")
        }

        Text {
            visible: root.alerts.length === 0
            text: "No active alerts"
            color: Style.text_dim
            font.family: Style.font_family
            font.pixelSize: Style.fs(-1)
        }

        // At most three cards show; the rest scroll so the detail keeps most of the height.
        ListView {
            id: alert_list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(3, root.alerts.length) * (root.card_h + spacing)
            visible: root.alerts.length > 0
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
                    anchors.margins: -3
                    radius: 11
                    visible: card.is_selected
                    color: Qt.alpha(card.tone, 0.16)
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    border.width: 1
                    border.color: card.is_selected ? Qt.alpha(card.tone, 0.85) : Qt.alpha(Theme.theme_primary_light, 0.2)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.alpha(card.is_selected ? card.tone : Theme.theme_primary_light, card.is_selected ? 0.3 : 0.1) }
                        GradientStop { position: 1; color: Qt.alpha(card.is_selected ? card.tone : Theme.theme_primary_strong, card.is_selected ? 0.08 : 0.03) }
                    }
                }

                Rectangle {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: parent.height - 16
                    radius: 1.5
                    color: card.tone
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 10
                    spacing: 0

                    Item { Layout.fillHeight: true }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: card.modelData.event
                        color: card.is_selected ? Theme.fg_strong : Theme.theme_primary_light
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-1)
                        font.weight: card.is_selected ? Font.Medium : Font.Light
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: card.modelData.severity + (card.modelData.ends ? " · until " + root.fmt_time(card.modelData.ends) : "")
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-4)
                    }

                    Item { Layout.fillHeight: true }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.on_select(card.index)
                }
            }
        }

        Rectangle {
            id: detail_panel
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: 4
            visible: !!root.selected
            radius: 8
            border.width: 1
            border.color: Qt.alpha(root.selected_color, 0.35)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(Theme.bg_shadow, 0.55) }
                GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary_strong, 0.14) }
            }

            Flickable {
                id: detail_flick
                anchors.fill: parent
                anchors.margins: 10
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
                        font.weight: Font.Medium
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
                        height: 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Qt.alpha(root.selected_color, 0.6) }
                            GradientStop { position: 1; color: "transparent" }
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

                    Caption {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        visible: !!root.selected && root.selected.instruction !== ""
                        text: "What to do"
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

            Rectangle {
                visible: detail_flick.contentHeight > detail_flick.height
                anchors.right: parent.right
                anchors.rightMargin: 3
                y: 8 + (detail_panel.height - 16 - height) * (detail_flick.contentY / Math.max(1, detail_flick.contentHeight - detail_flick.height))
                width: 2
                height: Math.max(16, (detail_panel.height - 16) * detail_flick.height / detail_flick.contentHeight)
                radius: 1
                color: Qt.alpha(root.selected_color, 0.7)
            }
        }
    }
}
