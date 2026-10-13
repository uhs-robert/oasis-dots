// home/quickshell/.config/quickshell/popups/ClockPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"
import "../theme"
import "../services"
import "../components/ps1" as Ps1
import "../components/ps2" as Ps2
import "../components/goldeneye" as Goldeneye
import "../components/snes" as SnesParts
import "snes" as Snes

Popup {
    id: root

    popup_name: "clock"
    title: root.nes ? root.day_title : Qt.formatDate(new Date(root.view_year, root.view_month, 1), "MMM yyyy").toUpperCase()
    preferred_width: 320
    footer_hint: root.agenda_on ? "h/l month · j/k year · arrows day · ,/. event · Enter open · n new · t/gg today · Tab zone · q close" : "h/l month · j/k year · t/gg today · Tab/[ ] zone · q close"
    body_height: content.implicitHeight + 24

    property date today: new Date()
    property int view_year: today.getFullYear()
    property int view_month: today.getMonth()
    jumps_enabled: true
    cursor_state: [root.view_year, root.view_month, Timezones.index, root.selected.getTime(), root.event_index]

    readonly property bool bios: root.st.console_views === "ps1"
    readonly property bool is_open: Popups.open_name === "clock"
    // A Dragon Quest adventure-log title, the day of the year ("DAY 284"), with the time at the right; the viewed month moves into the body.
    readonly property bool nes: root.st.console_views === "nes"
    readonly property date title_now: Timezones.shift(title_clock.date)
    readonly property int day_of_year: {
        const d = root.title_now;
        // Rounded because a DST change makes one day 23 or 25 hours long.
        return Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(d.getFullYear(), 0, 1)) / 86400000) + 1;
    }
    readonly property string day_title: "DAY " + root.day_of_year
    title_status: root.nes || root.st.title_status
    title_value: root.nes ? TimeFormat.format(root.title_now) : ""

    SystemClock {
        id: title_clock
        enabled: root.nes && root.is_open
        precision: SystemClock.Minutes
    }
    onIs_openChanged: if (is_open) {
        go_today();
        take_requested_day();
    }
    onJump_first: go_today()

    // Everything calendar-related stays off, and the popup looks as it always did, until a cache exists.
    readonly property bool agenda_on: CalendarState.configured
    property date selected: today
    property int event_index: 0
    readonly property var day_events: CalendarState.events_on(root.selected)
    readonly property int agenda_rows: 5
    // The agenda scrolls to keep the chosen event in view.
    readonly property int agenda_first: Math.max(0, Math.min(root.event_index - root.agenda_rows + 1, root.day_events.length - root.agenda_rows))
    readonly property var agenda_events: root.day_events.slice(root.agenda_first, root.agenda_first + root.agenda_rows)

    Connections {
        target: CalendarState
        function onRequested_dayChanged() {
            if (root.is_open) root.take_requested_day();
        }
    }

    function take_requested_day() {
        const d = CalendarState.parse_day(CalendarState.requested_day);
        CalendarState.requested_day = "";
        if (d) select_day(d);
    }

    // Lands on the event under way or the next one to start, so Enter joins what matters; a past day starts at its top.
    function first_open_event(date) {
        const list = CalendarState.events_on(date);
        const now = Date.now();
        const i = list.findIndex(e => !e.all_day && e.end_ms > now);
        return i < 0 ? 0 : i;
    }

    function select_day(date) {
        selected = date;
        view_year = date.getFullYear();
        view_month = date.getMonth();
        event_index = first_open_event(date);
    }

    function move_day(days) {
        const d = new Date(selected);
        d.setDate(d.getDate() + days);
        select_day(d);
    }

    // After the view moves by month or year, the selection follows to the same day of month.
    function follow_view() {
        const last = new Date(view_year, view_month + 1, 0).getDate();
        select_day(new Date(view_year, view_month, Math.min(selected.getDate(), last)));
    }

    function step_event(step) {
        event_index = Math.max(0, Math.min(event_index + step, day_events.length - 1));
    }

    function open_url(url) {
        if (!/^https:\/\//.test(url)) return;
        Quickshell.execDetached(["sh", "-c", "if command -v firefox >/dev/null; then exec firefox --new-tab \"$1\"; else exec xdg-open \"$1\"; fi", "sh", url]);
        Popups.close();
    }

    // Joins the Meet link, else the event page, else that day in Google Calendar.
    function open_event() {
        const e = day_events[event_index];
        const day_url = "https://calendar.google.com/calendar/r/day/" + selected.getFullYear() + "/" + (selected.getMonth() + 1) + "/" + selected.getDate();
        open_url(e ? (e.meet_url || e.event_url || day_url) : day_url);
    }

    // Google's prefilled new-event form: 9:00 to 10:00 on the selected day, or the next hour for today.
    function new_event() {
        const start = new Date(selected);
        const now = new Date();
        start.setHours(is_same_day(selected, now) && now.getHours() >= 8 ? Math.min(now.getHours() + 1, 22) : 9, 0, 0, 0);
        const end = new Date(start.getTime() + 3600000);
        const stamp = d => Qt.formatDateTime(d, "yyyyMMdd'T'HHmmss");
        open_url("https://calendar.google.com/calendar/render?action=TEMPLATE&dates=" + stamp(start) + "/" + stamp(end));
    }

    function go_today() {
        const d = new Date();
        today = d;
        select_day(d);
    }

    function prev_month() {
        if (view_month === 0) {
            view_month = 11;
            view_year -= 1;
        } else {
            view_month -= 1;
        }
        follow_view();
    }

    function next_month() {
        if (view_month === 11) {
            view_month = 0;
            view_year += 1;
        } else {
            view_month += 1;
        }
        follow_view();
    }

    function change_year(step) {
        view_year += step;
        follow_view();
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
        const start_offset = (first.getDay() - week_start + 7) % 7;
        const start = new Date(view_year, view_month, 1 - start_offset);
        const weeks = [];
        for (let w = 0; w < 6; w++) {
            const days = [];
            for (let d = 0; d < 7; d++) {
                const cur = new Date(start);
                cur.setDate(start.getDate() + w * 7 + d);
                days.push(cur);
            }
            weeks.push({ week_num: week_number(days[(4 - week_start + 7) % 7]), days: days });
        }
        return weeks;
    }

    readonly property int week_start: {
        const choice = ClockSettings.week_start;
        return choice === "sunday" ? 0 : choice === "monday" ? 1 : Qt.locale().firstDayOfWeek % 7;
    }
    readonly property var weeks: build_weeks()
    readonly property var weekday_headers: {
        const loc = Qt.locale();
        return [0, 1, 2, 3, 4, 5, 6].map(d => loc.dayName((week_start + d) % 7 || 7, Locale.ShortFormat).slice(0, 2));
    }

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
                    is_today: is_same_day(day, today),
                    date: day,
                    has_events: CalendarState.has_events(day)
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
    readonly property int grid_font_size: available_cell_width < 20 ? root.st.fs(-2) : root.st.fs(-1)

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: main_column.implicitHeight
        focus: true

        Keys.onPressed: event => {
            const before = root.cursor_key();
            if (event.key === Qt.Key_H) {
                root.prev_month();
                root.play_if_moved(before);
                event.accepted = true;
            } else if (event.key === Qt.Key_L) {
                root.next_month();
                root.play_if_moved(before);
                event.accepted = true;
            } else if (event.key === Qt.Key_J) {
                root.change_year(1);
                root.play_if_moved(before);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.change_year(-1);
                root.play_if_moved(before);
                event.accepted = true;
            } else if (event.key === Qt.Key_BracketRight || event.key === Qt.Key_Tab) {
                Timezones.cycle(1);
                root.play_if_moved(before);
                event.accepted = true;
            } else if (event.key === Qt.Key_BracketLeft || event.key === Qt.Key_Backtab) {
                Timezones.cycle(-1);
                root.play_if_moved(before);
                event.accepted = true;
            } else if (event.key === Qt.Key_T) {
                root.go_today();
                root.play_if_moved(before);
                event.accepted = true;
            } else if (root.agenda_on && event.key === Qt.Key_Left) {
                root.move_day(-1);
                root.play_if_moved(before);
                event.accepted = true;
            } else if (root.agenda_on && event.key === Qt.Key_Right) {
                root.move_day(1);
                root.play_if_moved(before);
                event.accepted = true;
            } else if (root.agenda_on && event.key === Qt.Key_Up) {
                root.move_day(-7);
                root.play_if_moved(before);
                event.accepted = true;
            } else if (root.agenda_on && event.key === Qt.Key_Down) {
                root.move_day(7);
                root.play_if_moved(before);
                event.accepted = true;
            } else if (root.agenda_on && (event.key === Qt.Key_Comma || event.key === Qt.Key_Period)) {
                root.step_event(event.key === Qt.Key_Period ? 1 : -1);
                root.play_if_moved(before);
                event.accepted = true;
            } else if (root.agenda_on && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                ThemeAudio.play("confirm");
                root.open_event();
                event.accepted = true;
            } else if (root.agenda_on && event.key === Qt.Key_N) {
                ThemeAudio.play("confirm");
                root.new_event();
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
                readonly property Component view: root.st.frame_watch ? watch_clock : ({ snes: snes_clock, ps1: ps1_clock, ps2: ps2_clock })[root.st.console_views] || null
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
                    id: watch_clock
                    Goldeneye.ClockFace {
                        running: root.is_open
                    }
                }

                Component {
                    id: ps2_clock
                    Ps2.ClockScreen {
                        running: root.is_open
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
                        font.pixelSize: root.st.fs(-2)
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
                            onClicked: {
                                Timezones.index = zone_label.index;
                                ThemeAudio.play("cursor");
                            }
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
                        readonly property bool chosen: root.agenda_on && modelData.kind === "day" && root.is_same_day(modelData.date, root.selected)

                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        implicitHeight: cell_text.implicitHeight + (root.agenda_on ? 5 : 0)

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
                            color: cell.marked ? root.st.title_fg : cell.modelData.kind === "header" ? root.st.text_muted : cell.modelData.kind === "weeknum" ? root.st.text_dim : cell.modelData.is_today ? Style.pal.today : (cell.modelData.in_month ? root.st.text_fg : root.st.text_muted)
                            font.underline: cell.modelData.kind === "day" && cell.modelData.is_today === true && !root.st.marker_fill
                            font.bold: cell.marked || cell.chosen
                        }

                        Rectangle {
                            visible: cell.chosen
                            anchors.fill: parent
                            radius: 2
                            color: "transparent"
                            border.width: 1
                            border.color: cell.marked ? root.st.title_fg : root.st.text_accent
                        }

                        Rectangle {
                            visible: root.agenda_on && cell.modelData.has_events === true
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: 4
                            height: 4
                            radius: 2
                            color: cell.marked ? root.st.title_fg : root.st.text_accent
                        }

                        MouseArea {
                            enabled: root.agenda_on && cell.modelData.kind === "day"
                            anchors.fill: parent
                            onClicked: {
                                root.select_day(cell.modelData.date);
                                ThemeAudio.play("cursor");
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: agenda
                visible: root.agenda_on
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: Qt.formatDate(root.selected, "ddd MMM d") + (CalendarState.error !== "" ? " (sync error, may be stale)" : "")
                    color: root.st.text_accent
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-1)
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    visible: root.day_events.length === 0
                    text: "No events"
                    color: root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-1)
                }

                Repeater {
                    model: root.agenda_events

                    RowLayout {
                        id: agenda_row
                        required property var modelData
                        required property int index

                        readonly property bool chosen: root.agenda_first + index === root.event_index
                        readonly property bool live: CalendarState.is_live(modelData)

                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.preferredWidth: 8
                            text: agenda_row.chosen ? ">" : ""
                            color: root.st.text_accent
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-1)
                        }

                        Text {
                            Layout.preferredWidth: Math.ceil(time_floor.advanceWidth)
                            text: agenda_row.modelData.all_day ? "all day" : TimeFormat.format(new Date(agenda_row.modelData.start_ms))
                            color: agenda_row.live ? Style.pal.today : root.st.text_dim
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-1)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: agenda_row.modelData.title
                            color: agenda_row.chosen ? root.st.text_fg : root.st.text_dim
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-1)
                            font.bold: agenda_row.chosen
                            elide: Text.ElideRight
                        }
                    }
                }

                Text {
                    visible: root.day_events.length > root.agenda_first + root.agenda_rows
                    text: "+" + (root.day_events.length - root.agenda_first - root.agenda_rows) + " more"
                    color: root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-2)
                }

                TextMetrics {
                    id: time_floor
                    text: TimeFormat.h24 ? "00:00" : "00:00pm"
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-1)
                }
            }
        }
    }
}
