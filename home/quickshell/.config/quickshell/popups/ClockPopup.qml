// home/quickshell/.config/quickshell/popups/ClockPopup.qml
import QtQuick
import QtQuick.Layouts
import "../components"
import "../theme"
import "../services"

Popup {
    id: root

    popup_name: "clock"
    title: Qt.formatDate(new Date(root.view_year, root.view_month, 1), "MMM yyyy").toUpperCase()
    preferred_width: 320
    footer_hint: "h/l month · j/k year · t/gg today · [ ] zone · q close"
    body_height: content.implicitHeight + 24

    property date today: new Date()
    property int view_year: today.getFullYear()
    property int view_month: today.getMonth()
    jumps_enabled: true

    readonly property bool is_open: Popups.open_name === "clock"
    onIs_openChanged: if (is_open) go_today()
    onJump_first: go_today()

    function go_today() {
        const d = new Date();
        today = d;
        view_year = d.getFullYear();
        view_month = d.getMonth();
    }

    function prev_month() {
        if (view_month === 0) {
            view_month = 11;
            view_year -= 1;
        } else {
            view_month -= 1;
        }
    }

    function next_month() {
        if (view_month === 11) {
            view_month = 0;
            view_year += 1;
        } else {
            view_month += 1;
        }
    }

    function is_same_day(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    // ISO-8601 week number.
    function week_number(d) {
        const dt = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const day_num = (dt.getUTCDay() + 6) % 7;
        dt.setUTCDate(dt.getUTCDate() - day_num + 3);
        const first_thursday = new Date(Date.UTC(dt.getUTCFullYear(), 0, 4));
        const diff_days = (dt - first_thursday) / 86400000 - 3 + ((first_thursday.getUTCDay() + 6) % 7);
        return 1 + Math.round(diff_days / 7);
    }

    function build_weeks() {
        const first = new Date(view_year, view_month, 1);
        const start_offset = (first.getDay() + 6) % 7;
        const start = new Date(view_year, view_month, 1 - start_offset);
        const weeks = [];
        for (let w = 0; w < 6; w++) {
            const days = [];
            for (let d = 0; d < 7; d++) {
                const cur = new Date(start);
                cur.setDate(start.getDate() + w * 7 + d);
                days.push(cur);
            }
            weeks.push({ week_num: week_number(days[0]), days: days });
        }
        return weeks;
    }

    readonly property var weeks: build_weeks()
    readonly property var weekday_headers: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    readonly property var flat_cells: {
        const cells = [];
        cells.push({ kind: "corner", text: "" });
        for (const h of weekday_headers) cells.push({ kind: "header", text: h });
        for (const week of weeks) {
            cells.push({ kind: "weeknum", text: String(week.week_num) });
            for (const day of week.days) {
                cells.push({
                    kind: "day",
                    text: String(day.getDate()),
                    in_month: day.getMonth() === view_month,
                    is_today: is_same_day(day, today)
                });
            }
        }
        return cells;
    }

    // Equal-width columns need the exact available width, not a guess, so the grid never clips.
    readonly property real grid_column_spacing: 4
    readonly property real available_cell_width: (content.width - grid_column_spacing * 7) / 8
    readonly property int grid_font_size: available_cell_width < 20 ? root.st.font_size - 2 : root.st.font_size - 1

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: main_column.implicitHeight
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_H) {
                root.prev_month();
                event.accepted = true;
            } else if (event.key === Qt.Key_L) {
                root.next_month();
                event.accepted = true;
            } else if (event.key === Qt.Key_J) {
                root.view_year += 1;
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.view_year -= 1;
                event.accepted = true;
            } else if (event.key === Qt.Key_BracketRight) {
                Timezones.cycle(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_BracketLeft) {
                Timezones.cycle(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_T) {
                root.go_today();
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 8

            Text {
                visible: !root.has_title
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDate(new Date(root.view_year, root.view_month, 1), "MMMM yyyy")
                color: root.st.text_fg
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size
                font.bold: true
            }

            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10

                Repeater {
                    model: Timezones.zones

                    Text {
                        id: zone_label
                        required property int index

                        readonly property bool is_active: index === Timezones.index

                        text: Timezones.abbrevs[index] || "..."
                        color: is_active ? (root.st.marker_fill ? root.st.title_fg : root.st.text_accent) : root.st.text_muted
                        font.family: root.st.font_family
                        font.pixelSize: root.st.font_size - 2
                        font.bold: is_active
                        font.underline: is_active && !root.st.marker_fill

                        Rectangle {
                            z: -1
                            visible: zone_label.is_active && root.st.marker_fill
                            anchors.fill: parent
                            anchors.leftMargin: -4
                            anchors.rightMargin: -4
                            color: root.st.title_bg
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Timezones.index = zone_label.index
                        }
                    }
                }
            }

            GridLayout {
                id: grid
                Layout.fillWidth: true
                columns: 8
                rowSpacing: 4
                columnSpacing: root.grid_column_spacing

                Repeater {
                    model: root.flat_cells

                    Text {
                        id: cell
                        required property var modelData
                        readonly property bool marked: modelData.kind === "day" && modelData.is_today === true && root.st.marker_fill

                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideNone
                        text: modelData.text
                        font.family: root.st.font_family
                        font.pixelSize: modelData.kind === "header" || modelData.kind === "weeknum" ? root.grid_font_size - 1 : root.grid_font_size
                        color: cell.marked ? root.st.title_fg : modelData.kind === "header" ? root.st.text_muted : modelData.kind === "weeknum" ? root.st.text_dim : modelData.is_today ? Theme.theme_accent : (modelData.in_month ? root.st.text_fg : root.st.text_muted)
                        font.underline: modelData.kind === "day" && modelData.is_today === true && !root.st.marker_fill
                        font.bold: cell.marked

                        Rectangle {
                            z: -1
                            visible: cell.marked
                            anchors.fill: parent
                            color: root.st.title_bg
                        }
                    }
                }
            }
        }
    }
}
