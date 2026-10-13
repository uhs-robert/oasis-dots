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
    footer_hint: root.day_level ? "j/k event · Enter join · h/Esc back · n new · q close" : root.agenda_on ? "h/l day · j/k week · H/L month · J/K year · Enter day · n new · t/gg today · Tab/[ ] zone · q close" : "h/l day · j/k week · H/L month · J/K year · n new · t/gg today · Tab/[ ] zone · q close"
    // The ? view describes both levels, whichever one is showing.
    key_help: root.agenda_on ? "h/l day · j/k week · H/L month · J/K year · Enter open the day · n new · t/gg today · Tab/[ ] zone · q close · j/k event (in a day) · Enter join (in a day) · h/Esc back to the grid" : "h/l day · j/k week · H/L month · J/K year · n new · t/gg today · Tab/[ ] zone · q close"
    body_height: content.implicitHeight + 24

    property date today: new Date()
    property int view_year: today.getFullYear()
    property int view_month: today.getMonth()
    jumps_enabled: true
    cursor_state: [root.view_year, root.view_month, Timezones.index, root.selected.getTime(), root.event_index, root.day_level]

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
    property string chosen_key: ""
    readonly property var day_events: CalendarState.events_on(root.selected)
    // Two levels: the grid previews the cursor day's agenda; Enter opens that day, where an event is highlighted and detailed.
    property bool day_level: false
    // The grid lists more events; at day level the details panel takes the rows below the list.
    readonly property int grid_rows: 8
    readonly property int day_rows: 3
    readonly property int details_lines: 5
    readonly property int agenda_rows: root.day_level ? root.day_rows : root.grid_rows
    // The region holds the header, the list and its "more" line, and at day level the details, in whichever level is showing, so the popup never changes height.
    readonly property int agenda_lines: Math.max(root.grid_rows + 2, root.day_rows + 2 + root.details_lines)
    // The day-level list scrolls to keep the chosen event in view.
    readonly property int agenda_first: root.day_level ? Math.max(0, Math.min(root.event_index - root.agenda_rows + 1, root.day_events.length - root.agenda_rows)) : 0
    readonly property var chosen_event: root.day_level ? root.day_events[root.event_index] || null : null
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
        if (d) {
            root.day_level = false;
            select_day(d);
        }
    }

    function enter_day() {
        root.day_level = true;
        event_index = first_open_event(selected);
        remember_choice();
    }

    function leave_day() {
        root.day_level = false;
    }

    function pick_event(index) {
        root.day_level = true;
        event_index = index;
        remember_choice();
    }

    // What Enter does with an event, in the details panel's words.
    function join_label(e) {
        const host = /^https:\/\/([^\/]+)/.exec(e.join_url || "");
        if (!host) return "Opens in Google Calendar";
        const name = host[1].toLowerCase();
        if (name === "meet.google.com") return "Google Meet";
        if (name === "teams.microsoft.com" || name === "teams.live.com") return "Microsoft Teams";
        return "Joins " + name;
    }

    // Lands on the meeting under way or the next to start, so Enter joins what matters; other days start at their top.
    function first_open_event(date) {
        const list = CalendarState.events_on(date);
        const now = Date.now();
        const i = list.findIndex(e => CalendarState.is_meeting(e) && e.end_ms > now);
        return i < 0 ? 0 : i;
    }

    function select_day(date) {
        selected = date;
        view_year = date.getFullYear();
        view_month = date.getMonth();
        event_index = first_open_event(date);
        remember_choice();
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
        remember_choice();
    }

    function event_key(e) {
        return e ? e.uid + "@" + e.start_ms : "";
    }

    function remember_choice() {
        chosen_key = event_key(day_events[event_index]);
    }

    // A reload can reorder or drop events; the cursor follows the one it was on, else stays in range.
    onDay_eventsChanged: {
        const i = day_events.findIndex(e => event_key(e) === chosen_key);
        event_index = i >= 0 ? i : Math.max(0, Math.min(event_index, day_events.length - 1));
        remember_choice();
    }

    // Opens the first candidate that is an https link, once the popup has let go of the keyboard.
    function open_first_link(candidates) {
        const url = candidates.find(u => /^https:\/\//.test(u));
        if (!url) return;
        Popups.after_close(() => Quickshell.execDetached(["sh", "-c", "if command -v firefox >/dev/null; then exec firefox --new-tab \"$1\"; else exec xdg-open \"$1\"; fi", "sh", url]));
    }

    // Joins the meeting link, else the event page, else that day in Google Calendar.
    function open_event() {
        const e = day_events[event_index];
        const day_url = "https://calendar.google.com/calendar/r/day/" + selected.getFullYear() + "/" + (selected.getMonth() + 1) + "/" + selected.getDate();
        open_first_link(e ? [e.join_url, e.event_url, day_url] : [day_url]);
    }

    // Google's prefilled new-event form, in UTC. On the selected day it starts at 9:00; for today at the next whole hour
    // (but not before 9:00), and once that is past 22:00 at 9:00 tomorrow, so the start is never in the past.
    function new_event() {
        const now = new Date();
        const start = new Date(selected);
        if (is_same_day(selected, now)) {
            const next_hour = now.getHours() + 1;
            if (next_hour > 22) start.setDate(start.getDate() + 1);
            start.setHours(next_hour > 22 ? 9 : Math.max(next_hour, 9), 0, 0, 0);
        } else {
            start.setHours(9, 0, 0, 0);
        }
        const end = new Date(start.getTime() + 3600000);
        const stamp = d => d.toISOString().replace(/[-:]/g, "").replace(/\.\d+/, "");
        open_first_link(["https://calendar.google.com/calendar/render?action=TEMPLATE&dates=" + stamp(start) + "/" + stamp(end)]);
    }

    function go_today() {
        root.day_level = false;
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
            const shifted = (event.modifiers & Qt.ShiftModifier) !== 0;
            const key = event.key;
            const accept_only = () => {
                event.accepted = true;
            };
            if (key === Qt.Key_N) {
                ThemeAudio.play("confirm");
                root.new_event();
                return accept_only();
            }
            if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                if (!root.agenda_on) return;
                ThemeAudio.play("confirm");
                if (root.day_level) root.open_event();
                else root.enter_day();
                return accept_only();
            }
            if (key === Qt.Key_BracketRight || key === Qt.Key_Tab) {
                Timezones.cycle(1);
            } else if (key === Qt.Key_BracketLeft || key === Qt.Key_Backtab) {
                Timezones.cycle(-1);
            } else if (root.day_level) {
                if (key === Qt.Key_J || key === Qt.Key_Down) root.step_event(1);
                else if (key === Qt.Key_K || key === Qt.Key_Up) root.step_event(-1);
                else if (key === Qt.Key_Escape || key === Qt.Key_Left || (key === Qt.Key_H && !shifted)) root.leave_day();
                else return;
            } else if (key === Qt.Key_H && shifted) {
                root.prev_month();
            } else if (key === Qt.Key_L && shifted) {
                root.next_month();
            } else if (key === Qt.Key_J && shifted) {
                root.change_year(1);
            } else if (key === Qt.Key_K && shifted) {
                root.change_year(-1);
            } else if (key === Qt.Key_H || key === Qt.Key_Left) {
                root.move_day(-1);
            } else if (key === Qt.Key_L || key === Qt.Key_Right) {
                root.move_day(1);
            } else if (key === Qt.Key_J || key === Qt.Key_Down) {
                root.move_day(7);
            } else if (key === Qt.Key_K || key === Qt.Key_Up) {
                root.move_day(-7);
            } else if (key === Qt.Key_T) {
                root.go_today();
            } else {
                return;
            }
            root.play_if_moved(before);
            event.accepted = true;
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
                        readonly property bool is_day: modelData.kind === "day"
                        readonly property bool chosen: is_day && root.is_same_day(modelData.date, root.selected)

                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        // Day cells pad around the digits so the selection outline has room, and below them for the event dot.
                        implicitHeight: cell_text.implicitHeight + (is_day ? (root.agenda_on ? 8 : 6) : 0)

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
                            y: cell.is_day ? 3 : 0
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
                            anchors.bottomMargin: 2
                            width: 4
                            height: 4
                            radius: 2
                            color: cell.marked ? root.st.title_fg : root.st.text_accent
                        }

                        MouseArea {
                            enabled: cell.is_day
                            anchors.fill: parent
                            onClicked: {
                                root.select_day(cell.modelData.date);
                                if (root.agenda_on) root.enter_day();
                                ThemeAudio.play("cursor");
                            }
                        }
                    }
                }
            }

            Item {
                id: agenda_region
                visible: root.agenda_on
                Layout.fillWidth: true
                Layout.preferredHeight: root.agenda_lines * time_floor.height + (root.agenda_lines - 1) * 2

                ColumnLayout {
                    id: agenda
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
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

                            readonly property bool chosen: root.day_level && root.agenda_first + index === root.event_index
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

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.pick_event(root.agenda_first + agenda_row.index);
                                    ThemeAudio.play("cursor");
                                }
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
                }

                // Pinned below the day-level list's rows, so it does not move as the list shortens.
                ColumnLayout {
                    id: details
                    visible: root.chosen_event !== null
                    y: (root.day_rows + 2) * (time_floor.height + 2)
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 2

                    Repeater {
                        model: root.chosen_event ? [
                            { text: (root.chosen_event.all_day ? "All day" : TimeFormat.format(new Date(root.chosen_event.start_ms)) + " - " + TimeFormat.format(new Date(root.chosen_event.end_ms))) + (root.chosen_event.status === "tentative" ? " · Tentative" : ""), bold: false },
                            { text: root.chosen_event.title, bold: true },
                            { text: root.chosen_event.location, bold: false },
                            { text: [root.chosen_event.organizer, root.chosen_event.guests > 0 ? root.chosen_event.guests + (root.chosen_event.guests === 1 ? " guest" : " guests") : ""].filter(t => t !== "").join(" · "), bold: false },
                            { text: root.join_label(root.chosen_event), bold: false }
                        ].filter(l => l.text !== "") : []

                        Text {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.text
                            color: modelData.bold ? root.st.text_fg : root.st.text_dim
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-1)
                            font.bold: modelData.bold
                            elide: Text.ElideRight
                        }
                    }
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
