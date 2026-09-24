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
    size_class: "large"
    preferred_width: 440
    fit_island: true
    title_value: WeatherState.has_data ? root.day_span + "D" : ""
    body_height: content.implicitHeight + 24
    key_help: "[ ] tabs · 1-" + root.tabs.length + " select · Tab view · h/l move · H/L jump · gg now · G end · r refresh" + (root.has_alerts ? " · a alerts" : "")

    readonly property var base_tab_names: ["Daily", "Hourly"]
    readonly property bool has_alerts: WeatherState.alerts.length > 0
    tabs: root.has_alerts ? root.base_tab_names.concat(["Alerts"]) : root.base_tab_names
    readonly property bool on_alerts_tab: root.has_alerts && root.current_tab === 2

    readonly property var daily_sub_names: ["Temp & Precip", "Wind", "UV", "Sunshine", "Sun & Moon"]
    readonly property int sun_moon_sub: 4
    readonly property var hourly_sub_names: ["Temp", "Precip", "Wind", "UV", "Humid", "Air"]
    readonly property int air_sub: 5
    sub_views: root.current_tab === 0 ? root.daily_sub_names : root.current_tab === 1 ? root.hourly_sub_names : []
    jumps_enabled: true

    // None of this is reset on close: the popup lives for the whole qs session, only visibility toggles.
    property int daily_sub: 0
    property int hourly_sub: 0
    property int day_cursor: 0
    // First day of the Daily window; Daily and Sun & Moon share it with day_cursor.
    property int day_first: 0
    property int hour_cursor: 0
    property int alert_cursor: 0

    readonly property int content_height: Style.px(400)
    readonly property bool on_air: root.current_tab === 1 && root.hourly_sub === root.air_sub
    readonly property int air_hours: Math.min(24, WeatherState.aq_hours.length)

    readonly property bool on_sun_moon: root.current_tab === 0 && root.daily_sub === root.sun_moon_sub
    readonly property int day_span: Math.max(1, daily_view.fit_days)

    function sync_day_window() {
        const n = root.day_span;
        let first = root.day_first;
        if (root.day_cursor < first) first = root.day_cursor;
        else if (root.day_cursor >= first + n) first = root.day_cursor - n + 1;
        root.day_first = Math.max(0, Math.min(first, WeatherState.days.length - n));
    }

    onDay_cursorChanged: root.sync_day_window()
    onDay_spanChanged: root.sync_day_window()

    Connections {
        target: WeatherState
        function onDaysChanged() { root.sync_day_window(); }
    }

    onCurrent_subChanged: {
        if (root.current_tab === 0) root.daily_sub = root.current_sub;
        else if (root.current_tab === 1) root.hourly_sub = root.current_sub;
    }
    onJump_first: root.go_now()
    onJump_last: root.go_end()

    readonly property bool is_open: Popups.open_name === "weather"
    onIs_openChanged: if (is_open) { WeatherState.refresh_if_due(); root.go_now(); }

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
            root.alert_cursor = root.wrap_index(root.alert_cursor, dir, 0, WeatherState.alerts.length);
        } else if (alerts_view) {
            alerts_view.scroll_detail(dir);
        }
    }

    function move_time(dir, jump) {
        if (root.current_tab === 0) root.move_day_cursor(dir, jump);
        else if (root.on_air) root.move_hour_cursor(dir, jump, root.air_hours, false);
        else if (root.current_tab === 1) root.move_hour_cursor(dir, jump, WeatherState.hours.length, true);
        else if (root.on_alerts_tab) root.move_alert_cursor(dir, jump);
    }

    function go_now() {
        root.day_cursor = 0;
        root.hour_cursor = 0;
        root.alert_cursor = 0;
        if (hourly_view) hourly_view.scroll_to_cursor();
    }

    function go_end() {
        if (root.current_tab === 0) {
            root.day_cursor = Math.max(0, WeatherState.days.length - 1);
        } else if (root.on_air) {
            root.hour_cursor = Math.max(0, root.air_hours - 1);
        } else if (root.current_tab === 1) {
            root.hour_cursor = Math.max(0, WeatherState.hours.length - 1);
            if (hourly_view) hourly_view.scroll_to_cursor();
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
        if (root.on_air) root.current_sub = 0;
        if (hourly_view) hourly_view.scroll_to_cursor();
    }

    function fmt_temp(t) {
        return Math.round(t) + "°" + WeatherState.unit_symbol();
    }

    function fmt_alert_time(iso) {
        return iso ? WeatherState.fmt_location_time(new Date(iso)) : "—";
    }

    function handle_key(event) {
        if (event.key === Qt.Key_A && root.has_alerts) {
            root.set_tab(root.tabs.length - 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_R) {
            WeatherState.refresh(true);
            event.accepted = true;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.current_tab === 0) {
            root.jump_to_hour_for_selected_day();
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

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 8

            // --- Current conditions header, shown above every tab ---
            Loader {
                Layout.fillWidth: true
                active: Style.weather_header !== ""
                visible: active
                sourceComponent: Style.weather_header === "spec" ? spec_header : Style.weather_header === "scope" ? scope_header : ring_header

                Component {
                    id: spec_header
                    WeatherSpec {}
                }

                Component {
                    id: scope_header
                    ScopeHeader {}
                }

                Component {
                    id: ring_header
                    RingHeader {}
                }
            }

            RowLayout {
                visible: Style.weather_header === ""
                Layout.fillWidth: true
                spacing: 14

                Image {
                    Layout.preferredWidth: Math.min(72, Math.max(40, main_column.width / 5))
                    Layout.preferredHeight: Layout.preferredWidth
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
                        color: WeatherState.has_data ? WeatherState.temp_color(WeatherState.current.temp) : Style.text_dim
                        font.family: Style.number_font
                        font.pixelSize: Style.font_size + 12
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: WeatherState.has_data ? WeatherState.current.cond : WeatherState.loading ? "Loading…" : "Unavailable: " + WeatherState.error
                        color: WeatherState.has_data || WeatherState.loading ? Theme.fg_core : Theme.warning
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size + 1
                    }

                    Text {
                        visible: WeatherState.has_data
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "Feels like " + (WeatherState.has_data ? root.fmt_temp(WeatherState.current.feels) : "")
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size - 2
                    }

                    Text {
                        visible: WeatherState.location_name !== ""
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        text: WeatherState.location_name
                        color: Style.text_dim
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size - 2
                    }
                }

                Text {
                    visible: WeatherState.stale
                    Layout.alignment: Qt.AlignTop
                    Layout.maximumWidth: main_column.width / 3
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    text: "Stale data" + (WeatherState.error ? ": " + WeatherState.error : "")
                    color: Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size - 3
                }
            }

            // --- Active-alert banner ---
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.has_alerts ? 28 : 0
                visible: root.has_alerts
                radius: Style.pill_chips ? height / 2 : Style.radius(4)
                readonly property color alert_color: WeatherState.alerts.length > 0 ? WeatherState.alert_color(WeatherState.alerts[0].severity) : Style.text_dim
                color: Style.boxed_cards ? Qt.alpha(alert_color, 0.1) : Theme.bg_surface
                border.width: Style.boxed_cards ? 1 : 0
                border.color: alert_color

                Hazard {
                    visible: Style.hazard.a > 0
                    x: 1
                    y: 1
                    width: 30
                    height: parent.height - 2
                    color: Theme.bg_crust
                    stripe: Style.hazard
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    anchors.leftMargin: Style.hazard.a > 0 ? 40 : 6
                    spacing: 8

                    Rectangle {
                        visible: Style.hazard.a === 0
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        radius: Style.radius(4)
                        color: WeatherState.alerts.length > 0 ? WeatherState.alert_color(WeatherState.alerts[0].severity) : Style.text_dim
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: WeatherState.alerts.length > 0
                            ? WeatherState.alerts[0].event + " · until " + root.fmt_alert_time(WeatherState.alerts[0].ends) + (WeatherState.alerts.length > 1 ? "  +" + (WeatherState.alerts.length - 1) + " more" : "")
                            : ""
                        color: WeatherState.alerts.length > 0 ? WeatherState.alert_color(WeatherState.alerts[0].severity) : Theme.fg_core
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size - 2
                        font.bold: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.set_tab(root.tabs.length - 1)
                }
            }

            TabRows {
                Layout.fillWidth: true
                labels: root.tabs
                current: root.current_tab
                tab_height: Style.px(26)
                onPicked: i => root.set_tab(i)
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.content_height

                DailyView {
                    id: daily_view
                    anchors.fill: parent
                    visible: root.current_tab === 0 && !root.on_sun_moon
                    day_cursor: root.day_cursor
                    first_day: root.day_first
                    sub: root.daily_sub
                    on_select: function (i) { root.day_cursor = i; }
                }

                HourlyView {
                    id: hourly_view
                    anchors.fill: parent
                    visible: root.current_tab === 1 && !root.on_air
                    hour_cursor: root.hour_cursor
                    sub: root.hourly_sub
                    on_select: function (i) { root.hour_cursor = i; }
                }

                AirView {
                    anchors.fill: parent
                    visible: root.on_air
                    hour_cursor: root.hour_cursor
                    on_select: function (i) { root.hour_cursor = i; }
                }

                SunMoonView {
                    anchors.fill: parent
                    visible: root.on_sun_moon
                    day_cursor: root.day_cursor
                    first_day: root.day_first
                    day_span: root.day_span
                    on_select: function (i) { root.day_cursor = i; }
                }

                AlertsView {
                    id: alerts_view
                    anchors.fill: parent
                    visible: root.on_alerts_tab
                    alert_cursor: root.alert_cursor
                    on_select: function (i) { root.alert_cursor = i; }
                }
            }

            // --- Sub-view chips (Daily/Hourly), under the content; the slot keeps its height on Alerts ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: sub_tabs.Layout.preferredHeight

                TabRows {
                    id: sub_tabs
                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: root.current_tab === 0 || root.current_tab === 1
                    chips: true
                    labels: root.sub_views
                    current: root.current_sub
                    reserve_labels: [root.daily_sub_names, root.hourly_sub_names]
                    onPicked: i => root.current_sub = i
                }
            }

            Text {
                text: WeatherState.updated > 0 ? "Updated " + WeatherState.format_hour(new Date(WeatherState.updated)) : "Never updated"
                color: Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.font_size - 4
            }

            MenuFooter {
                Layout.fillWidth: true
                wrap: true
                text: root.help_hint
            }
        }
    }
}
