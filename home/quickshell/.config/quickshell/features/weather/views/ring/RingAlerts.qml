pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.theme
import qs.styles.reticle.widgets
import qs.features.weather

// Active NWS alerts as a HUD list: a severity ring per alert, the selected one framed by the reticle, its text below.
// h/l or j/k select when there's more than one; with a single alert they scroll its detail text instead
// (see scroll_detail, called by the popup's key handler).
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
    readonly property real row_h: 38
    readonly property real ring_size: 18
    readonly property real reticle_size: 34

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

    // How far round its ring an alert's severity fills it.
    function severity_fraction(severity) {
        return { Extreme: 1, Severe: 0.75, Moderate: 0.5, Minor: 0.25 }[severity] || 0.1;
    }

    function scroll_detail(dir) {
        detail_flick.contentY = Math.max(0, Math.min(Math.max(0, detail_flick.contentHeight - detail_flick.height), detail_flick.contentY + dir * 40));
    }

    onAlert_cursorChanged: alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain)

    component CapsLabel: Text {
        color: Style.text_muted
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 2.5
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        CapsLabel {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: root.alerts.length === 0 ? "No active alerts" : "Alerts · " + root.alerts.length
            color: root.alerts.length === 0 ? Style.text_dim : Style.text_muted
        }

        // At most three rows show; the rest scroll so the detail keeps most of the height.
        ListView {
            id: alert_list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(3, root.alerts.length) * root.row_h
            visible: root.alerts.length > 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.alerts
            onCountChanged: Qt.callLater(() => alert_list.positionViewAtIndex(root.alert_cursor, ListView.Contain))

            delegate: Item {
                id: alert_row
                required property var modelData
                required property int index
                readonly property bool is_selected: alert_row.index === root.alert_cursor
                readonly property color tone: WeatherState.alert_color(alert_row.modelData.severity)
                readonly property real r: root.ring_size / 2 - 2

                width: ListView.view.width
                height: root.row_h

                Shape {
                    x: (root.reticle_size - root.ring_size) / 2
                    y: (parent.height - root.ring_size) / 2
                    width: root.ring_size
                    height: root.ring_size
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: 1
                        strokeColor: Qt.alpha(alert_row.tone, 0.3)
                        fillColor: "transparent"
                        PathAngleArc { centerX: root.ring_size / 2; centerY: root.ring_size / 2; radiusX: alert_row.r; radiusY: alert_row.r; startAngle: 0; sweepAngle: 360 }
                    }

                    ShapePath {
                        strokeWidth: 3
                        strokeColor: alert_row.tone
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap
                        PathAngleArc { centerX: root.ring_size / 2; centerY: root.ring_size / 2; radiusX: alert_row.r; radiusY: alert_row.r; startAngle: -90; sweepAngle: 360 * root.severity_fraction(alert_row.modelData.severity) }
                    }
                }

                Reticle {
                    visible: alert_row.is_selected
                    y: (parent.height - height) / 2
                    width: root.reticle_size
                    height: root.reticle_size
                    color: Style.hairline
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: root.reticle_size + 8
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: alert_row.modelData.event
                        color: alert_row.is_selected ? Style.text_strong : Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                        font.letterSpacing: 0.5
                    }

                    CapsLabel {
                        width: parent.width
                        elide: Text.ElideRight
                        text: alert_row.modelData.severity + (alert_row.modelData.ends ? " · until " + root.fmt_time(alert_row.modelData.ends) : "")
                        color: alert_row.is_selected ? alert_row.tone : Style.text_dim
                        font.letterSpacing: 2
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.on_select(alert_row.index)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            visible: !!root.selected
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Style.hairline }
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
            visible: !!root.selected
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
                    color: root.selected ? WeatherState.alert_color(root.selected.severity) : Style.text_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size
                    font.bold: true
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 2

                    CapsLabel { text: "From" }
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: root.selected ? root.fmt_time(root.selected.onset) : ""; color: Style.text_strong; font.family: Style.font_family; font.pixelSize: Style.fs(-3); font.letterSpacing: 0.5 }
                    CapsLabel { text: "Until" }
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: root.selected ? root.fmt_time(root.selected.ends) : ""; color: Style.text_strong; font.family: Style.font_family; font.pixelSize: Style.fs(-3); font.letterSpacing: 0.5 }
                    CapsLabel { text: "Area" }
                    Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.selected ? root.selected.area : ""; color: Style.text_strong; font.family: Style.font_family; font.pixelSize: Style.fs(-3); font.letterSpacing: 0.5 }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 4
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Style.hairline_dim }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    wrapMode: Text.WordWrap
                    text: root.selected ? root.unwrap(root.selected.description) : ""
                    color: Style.pal.fg
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-2)
                }

                CapsLabel {
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
    }
}
