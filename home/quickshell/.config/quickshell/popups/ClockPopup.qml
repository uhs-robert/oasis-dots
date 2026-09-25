// home/quickshell/.config/quickshell/popups/ClockPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"
import "../theme"
import "../services"
import "../components/ps1" as Ps1
import "../components/ps2" as Ps2
import "../components/snes" as SnesParts
import "snes" as Snes

Popup {
    id: root

    popup_name: "clock"
    title: root.nes ? root.hud_title : Qt.formatDate(new Date(root.view_year, root.view_month, 1), "MMM yyyy").toUpperCase()
    preferred_width: 320
    footer_hint: "h/l month · j/k year · t/gg today · [ ] zone · q close"
    body_height: content.implicitHeight + 24

    property date today: new Date()
    property int view_year: today.getFullYear()
    property int view_month: today.getMonth()
    jumps_enabled: true

    readonly property bool bios: root.st.console_views === "ps1"
    readonly property bool is_open: Popups.open_name === "clock"
    // A Mario HUD title with today's date and time; the viewed month moves into the body.
    readonly property bool nes: root.st.console_views === "nes"
    readonly property string hud_title: {
        const d = Timezones.shift(hud_clock.date);
        return "WORLD " + (d.getMonth() + 1) + "-" + d.getDate() + "  TIME " + Qt.formatTime(d, "HH:mm");
    }

    SystemClock {
        id: hud_clock
        enabled: root.nes && root.is_open
        precision: SystemClock.Minutes
    }
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
    // The SNES calendar window keeps its cells clear of its border and drop shadow.
    readonly property real calendar_inset: root.st.console_views === "snes" ? 10 : 0
    readonly property real available_cell_width: (content.width - (root.calendar_inset > 0 ? root.calendar_inset * 2 + 3 : 0) - grid_column_spacing * 7) / 8
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

        // SNES: the zones and calendar sit in their own RPG window.
        Loader {
            active: root.st.console_views === "snes"
            x: main_column.x
            y: main_column.y + zone_row.y - 8
            width: main_column.width
            height: grid.y + grid.height - zone_row.y + 19
            sourceComponent: SnesParts.SnesWindow {}
        }

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 8

            // Console clock screens above the calendar.
            Loader {
                readonly property Component view: ({ snes: snes_clock, ps1: ps1_clock, ps2: ps2_clock })[root.st.console_views] || null
                active: !!view
                visible: active
                Layout.fillWidth: true
                sourceComponent: view

                Component {
                    id: snes_clock
                    Snes.SnesClockStatus {
                        running: root.is_open
                    }
                }

                Component {
                    id: ps1_clock
                    Ps1.SaveClock {
                        id: save_clock
                        running: root.is_open
                        week: root.week_number(save_clock.now)
                    }
                }

                Component {
                    id: ps2_clock
                    Ps2.ClockScreen {
                        running: root.visible
                    }
                }
            }

            Text {
                visible: !root.has_title || root.nes
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDate(new Date(root.view_year, root.view_month, 1), "MMMM yyyy")
                color: root.st.text_fg
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size
                font.bold: true
            }

            Row {
                id: zone_row
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: root.st.console_views === "snes" ? 6 : 0
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
                Layout.bottomMargin: root.st.console_views === "snes" ? 12 : 0
                Layout.leftMargin: root.calendar_inset
                Layout.rightMargin: root.calendar_inset > 0 ? root.calendar_inset + 3 : 0
                columns: 8
                rowSpacing: 4
                columnSpacing: root.grid_column_spacing

                Repeater {
                    model: root.flat_cells

                    Item {
                        id: cell
                        required property var modelData
                        readonly property bool marked: modelData.kind === "day" && modelData.is_today === true && root.st.marker_fill

                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        implicitHeight: cell_text.implicitHeight

                        Rectangle {
                            visible: cell.marked && !root.bios
                            anchors.fill: parent
                            color: root.st.title_bg
                        }

                        Loader {
                            active: cell.marked && root.bios
                            anchors.fill: parent
                            sourceComponent: Ps1.BiosPanel {
                                lit: true
                                radius: 3
                            }
                        }

                        Text {
                            id: cell_text
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideNone
                            text: cell.modelData.text
                            font.family: root.st.font_family
                            font.pixelSize: cell.modelData.kind === "header" || cell.modelData.kind === "weeknum" ? root.grid_font_size - 1 : root.grid_font_size
                            color: cell.marked ? root.st.title_fg : cell.modelData.kind === "header" ? root.st.text_muted : cell.modelData.kind === "weeknum" ? root.st.text_dim : cell.modelData.is_today ? Theme.theme_accent : (cell.modelData.in_month ? root.st.text_fg : root.st.text_muted)
                            font.underline: cell.modelData.kind === "day" && cell.modelData.is_today === true && !root.st.marker_fill
                            font.bold: cell.marked
                        }
                    }
                }
            }
        }
    }
}
