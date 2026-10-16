import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "WttrArt.js" as WttrArt

// Active NWS alerts as `curl ... | less`: a numbered list, then the selected alert as a man page in a pager whose status line
// reports the scroll position. j/k or h/l select when there's more than one; with a single alert h/l scroll the page instead
// (see scroll_detail, called by the popup's key handler).
Item {
    id: root

    property int alert_cursor: 0
    // Called with the clicked alert index; the popup owns alert_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real detail_y: 0
    property var on_detail_scroll: function (y) {}

    readonly property var alerts: WeatherState.alerts
    readonly property int selected_index: Math.max(0, Math.min(root.alerts.length - 1, root.alert_cursor))
    readonly property var selected: root.alerts[root.selected_index]

    readonly property int text_px: Style.fs(-3)
    // Reading metrics.font makes the advances rebind once the family and size land.
    readonly property real glyph_w: metrics.font.pixelSize > 0 ? Math.max(1, metrics.advanceWidth("M")) : 1
    readonly property int lh: Math.max(1, Math.ceil(metrics.height))
    readonly property int page_chars: Math.max(20, Math.floor(root.width / root.glyph_w))
    readonly property real indent: 4 * root.glyph_w
    readonly property int visible_rows: 4
    readonly property color inverse: Style.tab_active_fg

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

    // The pager moves in whole lines, three to a keypress like less's half-step on a small window.
    function scroll_detail(dir) {
        page.contentY = Math.max(0, Math.min(Math.max(0, page.contentHeight - page.height), page.contentY + dir * 3 * root.lh));
    }

    function severity_text(alert) {
        const urgency = (alert.urgency || "Unknown").toLowerCase();
        return alert.severity + (urgency !== "unknown" ? ", urgency " + urgency : "");
    }

    function man_header() {
        const edge = "NWS-ALERT(7)", mid = "Weather Manual";
        const gap = Math.max(2, root.page_chars - 2 * edge.length - mid.length);
        const left = Math.floor(gap / 2);
        return edge + " ".repeat(left) + mid + " ".repeat(gap - left) + edge;
    }

    // The pager's own status text: which lines of the page show, and how far down that is.
    readonly property string status: {
        const total = Math.max(1, Math.round(page.contentHeight / root.lh));
        const first = Math.round(page.contentY / root.lh) + 1;
        const shown = Math.max(1, Math.floor(page.height / root.lh));
        const last = Math.min(total, first + shown - 1);
        const place = last >= total ? "(END)" : Math.floor(last / total * 100) + "%";
        return "alert " + (root.selected_index + 1) + "/" + root.alerts.length + "  lines " + first + "-" + last + "/" + total + " " + place;
    }

    onSelected_indexChanged: {
        alert_list.positionViewAtIndex(root.selected_index, ListView.Contain);
        page.contentY = 0;
    }

    FontMetrics {
        id: metrics
        font.family: Style.font_family
        font.pixelSize: root.text_px
    }

    Text {
        visible: root.alerts.length === 0
        text: "No active alerts"
        color: Style.text_dim
        font.family: Style.font_family
        font.pixelSize: Style.fs(-1)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4
        visible: root.alerts.length > 0

        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: WttrArt.runs([["$ ", String(Theme.theme_secondary)], ["curl api.weather.gov/alerts/active | less", String(Theme.fg_core)]])
            font.family: Style.font_family
            font.pixelSize: root.text_px
        }

        // Only a few rows show; the rest scroll so the page keeps most of the height.
        ListView {
            id: alert_list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(root.visible_rows, root.alerts.length) * root.lh
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.alerts
            onCountChanged: Qt.callLater(() => alert_list.positionViewAtIndex(root.selected_index, ListView.Contain))

            delegate: Rectangle {
                id: alert_row
                required property var modelData
                required property int index
                readonly property bool current: alert_row.index === root.selected_index

                width: ListView.view.width
                height: root.lh
                color: alert_row.current ? Style.tab_active_bg : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.right: tag.left
                    anchors.rightMargin: root.glyph_w
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: String(alert_row.index + 1).padStart(2, " ") + ". " + alert_row.modelData.event
                    color: alert_row.current ? root.inverse : Style.text_fg
                    font.family: Style.font_family
                    font.pixelSize: root.text_px
                }

                Text {
                    id: tag
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "[" + alert_row.modelData.severity + "]"
                    color: alert_row.current ? root.inverse : WeatherState.alert_color(alert_row.modelData.severity)
                    font.family: Style.font_family
                    font.pixelSize: root.text_px
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.on_select(alert_row.index)
                }
            }
        }

        // Whole lines only, so the status line's line numbers are exact.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                id: page
                width: parent.width
                height: Math.floor(parent.height / root.lh) * root.lh
                clip: true
                contentWidth: width
                contentHeight: page_col.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                onContentYChanged: root.on_detail_scroll(page.contentY)
                Component.onCompleted: page.contentY = root.detail_y

                Column {
                    id: page_col
                    width: page.width

                    component Line: Text {
                        width: page_col.width
                        height: root.lh
                        elide: Text.ElideRight
                        color: Style.text_fg
                        font.family: Style.font_family
                        font.pixelSize: root.text_px
                    }

                    component Heading: Line {
                        font.bold: true
                        color: Style.text_strong
                    }

                    component Body: Text {
                        x: root.indent
                        width: page_col.width - root.indent
                        wrapMode: Text.WordWrap
                        color: Style.text_fg
                        font.family: Style.font_family
                        font.pixelSize: root.text_px
                        lineHeight: root.lh
                        lineHeightMode: Text.FixedHeight
                    }

                    component Gap: Item {
                        width: 1
                        height: root.lh
                    }

                    readonly property var alert: root.selected

                    Line { text: root.man_header(); color: Style.text_muted }
                    Gap {}

                    Heading { text: "NAME" }
                    Body {
                        text: page_col.alert ? page_col.alert.event + (page_col.alert.headline ? " - " + page_col.alert.headline : "") : ""
                        color: page_col.alert ? WeatherState.alert_color(page_col.alert.severity) : Style.text_fg
                        font.bold: true
                    }
                    Gap {}

                    Heading { text: "SEVERITY" }
                    Body {
                        text: page_col.alert ? root.severity_text(page_col.alert) : ""
                        color: page_col.alert ? WeatherState.alert_color(page_col.alert.severity) : Style.text_fg
                    }
                    Gap {}

                    Heading { text: "EFFECTIVE" }
                    Body { text: page_col.alert ? "from " + root.fmt_time(page_col.alert.onset) + "\nuntil " + root.fmt_time(page_col.alert.ends) : "" }
                    Gap {}

                    Heading { text: "AREA"; visible: !!page_col.alert && page_col.alert.area !== "" }
                    Body { text: page_col.alert ? page_col.alert.area : ""; visible: !!page_col.alert && page_col.alert.area !== "" }
                    Gap { visible: !!page_col.alert && page_col.alert.area !== "" }

                    Heading { text: "DESCRIPTION" }
                    Body { text: page_col.alert ? root.unwrap(page_col.alert.description) : "" }

                    Gap { visible: !!page_col.alert && page_col.alert.instruction !== "" }
                    Heading { text: "INSTRUCTIONS"; visible: !!page_col.alert && page_col.alert.instruction !== "" }
                    Body { text: page_col.alert ? root.unwrap(page_col.alert.instruction) : ""; visible: !!page_col.alert && page_col.alert.instruction !== "" }

                    Gap {}
                    Line { text: page_col.alert && page_col.alert.sender ? page_col.alert.sender : "NWS"; color: Style.text_muted }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.lh
            color: Style.tab_active_bg

            Text {
                anchors.fill: parent
                elide: Text.ElideRight
                text: root.status
                color: root.inverse
                font.family: Style.font_family
                font.pixelSize: root.text_px
            }
        }
    }
}
