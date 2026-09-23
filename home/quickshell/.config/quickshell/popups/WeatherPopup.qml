// home/quickshell/.config/quickshell/popups/WeatherPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"
import "../theme"
import "../services"
import "weather"

Popup {
    id: root

    popup_name: "weather"
    preferred_width: 760
    implicitHeight: content.implicitHeight + 24

    readonly property var base_tab_names: ["Daily", "Hourly", "Precipitation", "Sun & Moon", "Air"]
    readonly property bool has_alerts: WeatherState.alerts.length > 0
    readonly property var tab_names: root.has_alerts ? root.base_tab_names.concat(["Alerts"]) : root.base_tab_names
    readonly property bool on_alerts_tab: root.has_alerts && root.current_tab === 5

    readonly property var daily_sub_names: ["Temp & Precip", "Wind", "UV", "Sunshine"]
    readonly property var hourly_sub_names: ["Temperature", "Precipitation", "Wind", "UV", "Humidity"]

    // None of this is reset on close: the popup lives for the whole qs session, only visibility toggles.
    property int current_tab: 0
    property int daily_sub: 0
    property int hourly_sub: 0
    property int day_cursor: 0
    property int hour_cursor: 0
    property int alert_cursor: 0
    property double last_g_ms: 0

    readonly property int content_height: 400

    onTab_namesChanged: if (root.current_tab >= root.tab_names.length) root.current_tab = 0;

    readonly property bool is_open: Popups.open_name === "weather"
    onIs_openChanged: if (is_open) { WeatherState.refresh_if_due(); root.go_now(); }

    function set_tab(i) {
        root.current_tab = Math.max(0, Math.min(root.tab_names.length - 1, i));
    }

    function step_tab(delta) {
        root.current_tab = (root.current_tab + delta + root.tab_names.length) % root.tab_names.length;
    }

    function set_current_sub(i) {
        if (root.current_tab === 0) root.daily_sub = Math.max(0, Math.min(root.daily_sub_names.length - 1, i));
        else if (root.current_tab === 1) root.hourly_sub = Math.max(0, Math.min(root.hourly_sub_names.length - 1, i));
    }

    function step_current_sub(delta) {
        if (root.current_tab === 0) root.daily_sub = (root.daily_sub + delta + root.daily_sub_names.length) % root.daily_sub_names.length;
        else if (root.current_tab === 1) root.hourly_sub = (root.hourly_sub + delta + root.hourly_sub_names.length) % root.hourly_sub_names.length;
    }

    function move_day_cursor(dir, jump) {
        const n = Math.max(1, WeatherState.days.length);
        root.day_cursor = jump ? (dir < 0 ? 0 : n - 1) : Math.max(0, Math.min(n - 1, root.day_cursor + dir));
    }

    // Same hour, one day over: an index step of 24 is a good approximation even on a
    // partial first day (fewer than 24 hours before midnight).
    function shifted_hour_cursor(dir) {
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return 0;
        return Math.max(0, Math.min(hrs.length - 1, root.hour_cursor + 24 * dir));
    }

    function move_hour_cursor(dir, jump, n, is_hourly_tab) {
        n = Math.max(1, n);
        if (jump) root.hour_cursor = is_hourly_tab ? root.shifted_hour_cursor(dir) : (dir < 0 ? 0 : n - 1);
        else root.hour_cursor = Math.max(0, Math.min(n - 1, root.hour_cursor + dir));
        if (is_hourly_tab && hourly_view) hourly_view.scroll_to_cursor();
    }

    function move_alert_cursor(dir, jump) {
        const n = Math.max(1, WeatherState.alerts.length);
        if (jump) {
            root.alert_cursor = dir < 0 ? 0 : n - 1;
        } else if (WeatherState.alerts.length > 1) {
            root.alert_cursor = Math.max(0, Math.min(n - 1, root.alert_cursor + dir));
        } else if (alerts_view) {
            alerts_view.scroll_detail(dir);
        }
    }

    function move_time(dir, jump) {
        if (root.current_tab === 0 || root.current_tab === 3) root.move_day_cursor(dir, jump);
        else if (root.current_tab === 1) root.move_hour_cursor(dir, jump, WeatherState.hours.length, true);
        else if (root.current_tab === 2) root.move_hour_cursor(dir, jump, Math.min(12, WeatherState.hours.length), false);
        else if (root.current_tab === 4) root.move_hour_cursor(dir, jump, Math.min(24, WeatherState.aq_hours.length), false);
        else if (root.on_alerts_tab) root.move_alert_cursor(dir, jump);
    }

    function go_now() {
        root.day_cursor = 0;
        root.hour_cursor = 0;
        root.alert_cursor = 0;
        if (hourly_view) hourly_view.scroll_to_cursor();
    }

    function go_end() {
        if (root.current_tab === 0 || root.current_tab === 3) {
            root.day_cursor = Math.max(0, WeatherState.days.length - 1);
        } else if (root.current_tab === 1) {
            root.hour_cursor = Math.max(0, WeatherState.hours.length - 1);
            if (hourly_view) hourly_view.scroll_to_cursor();
        } else if (root.current_tab === 2) {
            root.hour_cursor = Math.max(0, Math.min(11, WeatherState.hours.length - 1));
        } else if (root.current_tab === 4) {
            root.hour_cursor = Math.max(0, Math.min(23, WeatherState.aq_hours.length - 1));
        } else if (root.on_alerts_tab) {
            root.alert_cursor = Math.max(0, WeatherState.alerts.length - 1);
        }
    }

    function jump_to_hour_for_selected_day() {
        const day = WeatherState.days[root.day_cursor];
        if (!day) return;
        const hrs = WeatherState.hours;
        const target_hour = root.day_cursor === 0 ? WeatherState.location_now().getUTCHours() : 12;
        let idx = hrs.findIndex(h => h.date === day.date && h.hour === target_hour);
        if (idx === -1) idx = hrs.findIndex(h => h.date === day.date);
        if (idx === -1) idx = 0;
        root.hour_cursor = idx;
        root.set_tab(1);
        if (hourly_view) hourly_view.scroll_to_cursor();
    }

    function fmt_temp(t) {
        return Math.round(t) + "°" + WeatherState.unit_symbol();
    }

    function fmt_alert_time(iso) {
        return iso ? WeatherState.fmt_location_time(new Date(iso)) : "—";
    }

    // --- Single key handler: every popup shortcut is dispatched from here ---
    function handle_key(event) {
        if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
            if (root.current_tab === 0 || root.current_tab === 1) root.step_current_sub(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Tab) {
            if (root.current_tab === 0 || root.current_tab === 1) root.step_current_sub(1);
            event.accepted = true;
        } else if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.tab_names.length) {
            root.set_tab(event.key - Qt.Key_1);
            event.accepted = true;
        } else if (event.key === Qt.Key_A && root.has_alerts) {
            root.set_tab(root.tab_names.length - 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_BracketLeft) {
            root.step_tab(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_BracketRight) {
            root.step_tab(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_R) {
            WeatherState.refresh(true);
            event.accepted = true;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.current_tab === 0) {
            root.jump_to_hour_for_selected_day();
            event.accepted = true;
        } else if (event.key === Qt.Key_G) {
            if (event.modifiers & Qt.ShiftModifier) {
                root.go_end();
            } else {
                const now_ms = Date.now();
                if (now_ms - root.last_g_ms < 500) { root.go_now(); root.last_g_ms = 0; }
                else root.last_g_ms = now_ms;
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_H) {
            root.move_time(-1, !!(event.modifiers & Qt.ShiftModifier));
            event.accepted = true;
        } else if (event.key === Qt.Key_L) {
            root.move_time(1, !!(event.modifiers & Qt.ShiftModifier));
            event.accepted = true;
        } else if (root.on_alerts_tab && event.key === Qt.Key_J) {
            root.move_alert_cursor(1, false);
            event.accepted = true;
        } else if (root.on_alerts_tab && event.key === Qt.Key_K) {
            root.move_alert_cursor(-1, false);
            event.accepted = true;
        }
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        implicitHeight: main_column.implicitHeight
        focus: true

        Keys.onPressed: event => root.handle_key(event)
        Keys.onTabPressed: event => root.handle_key(event)
        Keys.onBacktabPressed: event => root.handle_key(event)

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 8

            // --- Current conditions header, shown above every tab ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                Image {
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 72
                    readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                    source: WeatherState.has_data ? WeatherState.icon_source(WeatherState.current.code, WeatherState.current.is_day) : ""
                    visible: WeatherState.has_data
                    sourceSize.width: Math.ceil(144 * dpr)
                    sourceSize.height: Math.ceil(144 * dpr)
                    smooth: true
                }

                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true

                    Text {
                        text: WeatherState.has_data ? root.fmt_temp(WeatherState.current.temp) : "--°"
                        color: WeatherState.has_data ? WeatherState.temp_color(WeatherState.current.temp) : Theme.fg_dim
                        font.family: Theme.font_family
                        font.pixelSize: Theme.popup_font_size + 12
                        font.bold: true
                    }

                    Text {
                        text: WeatherState.has_data ? WeatherState.current.cond : WeatherState.loading ? "Loading…" : "Unavailable: " + WeatherState.error
                        color: WeatherState.has_data || WeatherState.loading ? Theme.fg_core : Theme.warning
                        font.family: Theme.font_family
                        font.pixelSize: Theme.popup_font_size + 1
                    }

                    Text {
                        visible: WeatherState.has_data
                        text: "Feels like " + (WeatherState.has_data ? root.fmt_temp(WeatherState.current.feels) : "")
                        color: Theme.fg_muted
                        font.family: Theme.font_family
                        font.pixelSize: Theme.popup_font_size - 2
                    }

                    Text {
                        visible: WeatherState.location_name !== ""
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        text: WeatherState.location_name
                        color: Theme.fg_dim
                        font.family: Theme.font_family
                        font.pixelSize: Theme.popup_font_size - 2
                    }
                }

                Text {
                    visible: WeatherState.stale
                    Layout.alignment: Qt.AlignTop
                    text: "Stale data" + (WeatherState.error ? ": " + WeatherState.error : "")
                    color: Theme.warning
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size - 3
                }
            }

            // --- Active-alert banner ---
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.has_alerts ? 28 : 0
                visible: root.has_alerts
                radius: 4
                color: Theme.bg_surface

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        radius: 4
                        color: WeatherState.alerts.length > 0 ? WeatherState.alert_color(WeatherState.alerts[0].severity) : Theme.fg_dim
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: WeatherState.alerts.length > 0
                            ? WeatherState.alerts[0].event + " · until " + root.fmt_alert_time(WeatherState.alerts[0].ends) + (WeatherState.alerts.length > 1 ? "  +" + (WeatherState.alerts.length - 1) + " more" : "")
                            : ""
                        color: WeatherState.alerts.length > 0 ? WeatherState.alert_color(WeatherState.alerts[0].severity) : Theme.fg_core
                        font.family: Theme.font_family
                        font.pixelSize: Theme.popup_font_size - 2
                        font.bold: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.set_tab(root.tab_names.length - 1)
                }
            }

            // --- Tab row ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: root.tab_names

                    Rectangle {
                        id: tab_chip
                        required property string modelData
                        required property int index

                        Layout.fillWidth: true
                        height: 26
                        radius: 4
                        color: tab_chip.index === root.current_tab ? Theme.bg_surface : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: tab_chip.modelData
                            color: tab_chip.index === root.current_tab ? Theme.theme_secondary : Theme.fg_muted
                            font.family: Theme.font_family
                            font.pixelSize: Theme.popup_font_size - 2
                            font.bold: tab_chip.index === root.current_tab
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.set_tab(tab_chip.index)
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.content_height

                DailyView {
                    anchors.fill: parent
                    visible: root.current_tab === 0
                    day_cursor: root.day_cursor
                    sub: root.daily_sub
                    on_select: function (i) { root.day_cursor = i; }
                }

                HourlyView {
                    id: hourly_view
                    anchors.fill: parent
                    visible: root.current_tab === 1
                    hour_cursor: root.hour_cursor
                    sub: root.hourly_sub
                    on_select: function (i) { root.hour_cursor = i; }
                }

                PrecipView {
                    anchors.fill: parent
                    visible: root.current_tab === 2
                    hour_cursor: root.hour_cursor
                    on_select: function (i) { root.hour_cursor = i; }
                }

                SunMoonView {
                    anchors.fill: parent
                    visible: root.current_tab === 3
                    day_cursor: root.day_cursor
                }

                AirView {
                    anchors.fill: parent
                    visible: root.current_tab === 4
                    hour_cursor: root.hour_cursor
                    on_select: function (i) { root.hour_cursor = i; }
                }

                AlertsView {
                    id: alerts_view
                    anchors.fill: parent
                    visible: root.on_alerts_tab
                    alert_cursor: root.alert_cursor
                    on_select: function (i) { root.alert_cursor = i; }
                }
            }

            // --- Sub-view chips (Daily/Hourly) or the selected time (others), under the content ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 28

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    visible: root.current_tab === 0 || root.current_tab === 1

                    Repeater {
                        model: root.current_tab === 0 ? root.daily_sub_names : root.current_tab === 1 ? root.hourly_sub_names : []

                        Rectangle {
                            id: sub_chip
                            required property string modelData
                            required property int index
                            readonly property bool active: sub_chip.index === (root.current_tab === 0 ? root.daily_sub : root.hourly_sub)

                            implicitWidth: sub_label.implicitWidth + 20
                            implicitHeight: 24
                            radius: 12
                            color: sub_chip.active ? Theme.bg_surface : "transparent"

                            Text {
                                id: sub_label
                                anchors.centerIn: parent
                                text: sub_chip.modelData
                                color: sub_chip.active ? Theme.theme_secondary : Theme.fg_muted
                                font.bold: sub_chip.active
                                font.family: Theme.font_family
                                font.pixelSize: Theme.popup_font_size - 3
                            }

                            MouseArea { anchors.fill: parent; onClicked: root.set_current_sub(sub_chip.index) }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.current_tab === 3
                    readonly property var d: WeatherState.days[root.day_cursor]
                    text: d ? d.weekday + (d.weekday !== "Today" ? " (" + d.date.substr(5) + ")" : "") : ""
                    color: Theme.fg_muted
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size - 3
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.current_tab === 2 || root.current_tab === 4
                    text: {
                        const hrs = root.current_tab === 2 ? WeatherState.hours.slice(0, 12) : WeatherState.aq_hours.slice(0, 24);
                        const r = hrs[Math.max(0, Math.min(hrs.length - 1, root.hour_cursor))];
                        return r ? WeatherState.format_hour(new Date(r.dt)) : "";
                    }
                    color: Theme.fg_muted
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size - 3
                }
            }

            Text {
                text: WeatherState.updated > 0 ? "Updated " + WeatherState.format_hour(new Date(WeatherState.updated)) : "Never updated"
                color: Theme.fg_dim
                font.family: Theme.font_family
                font.pixelSize: Theme.popup_font_size - 4
            }

            Text {
                text: "[ ] tabs · 1-5 select · Tab view · h/l move · H/L jump · gg now · G end · r refresh" + (root.has_alerts ? " · a alerts" : "")
                color: Theme.fg_dim
                font.family: Theme.font_family
                font.pixelSize: Theme.popup_font_size - 4
            }
        }
    }
}
