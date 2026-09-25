// home/quickshell/.config/quickshell/popups/KeeptabsPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../components"
import "../theme"
import "../services"

Popup {
    id: root

    popup_name: "keeptabs"
    preferred_width: 340
    body_height: content.implicitHeight + 24
    key_help: root.current_tab === 0
        ? "[ ] tabs · 1-2 select · j/k move · gg/G first/last · Enter/click focus"
        : "[ ] tabs · 1-2 select · r refresh"

    property var sessions: []
    property int selected: 0
    property bool stale: false
    readonly property int content_height: Style.px(300)

    tabs: ["Agents", "Usage"]
    jumps_enabled: root.current_tab === 0

    readonly property bool is_open: Popups.open_name === "keeptabs"
    onIs_openChanged: if (is_open) {
        root.selected = 0;
        root.refresh();
        if (root.current_tab === 1) ClaudeUsageState.refresh(false);
    }
    onSessionsChanged: selected = Math.max(0, Math.min(selected, sessions.length - 1));
    onCurrent_tabChanged: if (root.current_tab === 1) ClaudeUsageState.refresh(false);
    search_enabled: root.current_tab === 0
    search_rows: root.sessions.map(x => (x.title || "Untitled") + " " + (x.project || "") + " " + (x.agent || "claude"))
    search_cursor: root.selected
    onSearch_select: index => {
        root.selected = index;
        session_list.positionViewAtIndex(index, ListView.Contain);
    }
    onJump_first: root.go_first()
    onJump_last: root.go_last()

    function refresh() {
        if (!root.is_open) return;
        if (fetch_proc.running) root.stale = true;
        else fetch_proc.running = true;
    }

    // The tooltip lists each session's state, so it changes only when the list does; runs change every animation frame.
    Connections {
        target: KeeptabsState
        function onTooltipChanged() { root.refresh(); }
    }

    Process {
        id: fetch_proc
        command: ["sh", "-c", "exec ~/.local/bin/keeptabs-pick --json"]
        onExited: if (root.stale) {
            root.stale = false;
            root.refresh();
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.sessions = JSON.parse(text);
                } catch (e) {
                    console.warn("keeptabs-pick --json: " + e);
                }
            }
        }
    }

    function state_color(state) {
        if (state === "waiting") return Theme.error;
        if (state === "done") return Theme.ok;
        if (state === "running") return root.st.text_primary;
        return root.st.text_dim;
    }

    // Below 60% the primary color, 60-85% a warning, above that an error.
    function context_bar_color(pct) {
        if (pct >= 85) return Theme.error;
        if (pct >= 60) return Theme.warning;
        return root.st.text_primary;
    }

    function fmt_tokens(n) {
        if (n === null || n === undefined) return "0";
        if (n >= 1000000) return (n / 1000000).toFixed(1).replace(/\.0$/, "") + "M";
        if (n >= 1000) return Math.round(n / 1000) + "k";
        return String(n);
    }

    function age(since) {
        const s = Math.floor(Date.now() / 1000) - since;
        if (s < 60) return s + "s";
        if (s < 3600) return Math.floor(s / 60) + "m";
        return Math.floor(s / 3600) + "h";
    }

    function focus_session(id) {
        Quickshell.execDetached(["sh", "-c", "exec ~/.local/bin/keeptabs-pick --focus \"$1\"", "sh", id]);
        Popups.close();
    }

    function move_selected(delta) {
        if (root.sessions.length === 0) return;
        root.selected = root.wrap_index(root.selected, delta, 0, root.sessions.length);
        session_list.positionViewAtIndex(root.selected, ListView.Contain);
    }

    function go_first() {
        if (root.sessions.length === 0) return;
        root.selected = 0;
        session_list.positionViewAtIndex(root.selected, ListView.Contain);
    }

    function go_last() {
        if (root.sessions.length === 0) return;
        root.selected = root.sessions.length - 1;
        session_list.positionViewAtIndex(root.selected, ListView.Contain);
    }

    function handle_key(event) {
        if (root.current_tab === 1 && event.key === Qt.Key_R) {
            ClaudeUsageState.refresh(true);
            event.accepted = true;
        } else if (root.current_tab === 0 && event.key === Qt.Key_J) {
            root.move_selected(1);
            event.accepted = true;
        } else if (root.current_tab === 0 && event.key === Qt.Key_K) {
            root.move_selected(-1);
            event.accepted = true;
        } else if (root.current_tab === 0 && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.sessions[root.selected]) {
            root.focus_session(root.sessions[root.selected].id);
            event.accepted = true;
        }
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: main_column.implicitHeight
        focus: true

        Keys.onPressed: event => root.handle_key(event)

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 6

            // --- Tab row ---
            TabRows {
                Layout.fillWidth: true
                labels: root.tabs
                current: root.current_tab
                tab_height: Style.px(26)
                onPicked: index => root.set_tab(index)
            }

            // --- Content: fixed height so the popup never resizes between tabs ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.content_height

                Text {
                    anchors.centerIn: parent
                    visible: root.current_tab === 0 && root.sessions.length === 0
                    text: "No agent sessions"
                    color: root.st.text_dim
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-2)
                }

                ListView {
                    id: session_list
                    anchors.fill: parent
                    visible: root.current_tab === 0 && root.sessions.length > 0
                    clip: true
                    spacing: 4
                    model: root.sessions
                    currentIndex: root.selected

                    delegate: MenuRow {
                        id: session_row
                        required property var modelData
                        required property int index
                        readonly property bool has_context: session_row.modelData.context_pct !== null && session_row.modelData.context_pct !== undefined

                        width: session_list.width
                        height: Style.px(46)
                        selected: session_row.index === root.selected

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6 + session_row.inset
                            anchors.rightMargin: 6 + session_row.key_space
                            anchors.topMargin: 3
                            anchors.bottomMargin: 3
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: (session_row.modelData.state || "idle").toUpperCase()
                                    color: session_row.fg(root.state_color(session_row.modelData.state))
                                    font.family: root.st.font_family
                                    font.pixelSize: root.st.fs(-2)
                                    font.bold: true
                                }

                                RowLabel {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                    label: session_row.modelData.title || "Untitled"
                                    color: session_row.fg(root.st.text_fg)
                                    font.family: root.st.font_family
                                    font.pixelSize: root.st.fs(-1)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                RowLabel {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                    label: (session_row.modelData.agent || "claude") + " · " + (session_row.modelData.project || "") + " · " + (session_row.modelData.where || "") + " · " + root.age(session_row.modelData.since)
                                    color: session_row.fg(root.st.text_muted)
                                    font.family: root.st.font_family
                                    font.pixelSize: root.st.fs(-3)
                                }

                                Text {
                                    visible: session_row.has_context
                                    text: session_row.has_context ? session_row.modelData.context_pct + "% · " + root.fmt_tokens(session_row.modelData.context_used) + "/" + root.fmt_tokens(session_row.modelData.context_window) : ""
                                    color: session_row.fg(root.st.text_dim)
                                    font.family: root.st.font_family
                                    font.pixelSize: root.st.fs(-4)
                                }
                            }

                            Meter {
                                Layout.fillWidth: true
                                visible: session_row.has_context && root.st.segmented_levels
                                implicitHeight: 4
                                segment_count: 40
                                value: session_row.has_context ? session_row.modelData.context_pct / 100 : 0
                                on_color: session_row.has_context ? root.context_bar_color(session_row.modelData.context_pct) : root.st.meter_on
                                on_selection: session_row.selected
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: session_row.has_context ? 3 : 0
                                visible: session_row.has_context && !root.st.segmented_levels
                                radius: Style.radius(1.5)
                                color: Theme.bg_surface

                                Rectangle {
                                    width: session_row.has_context ? parent.width * Math.max(0, Math.min(100, session_row.modelData.context_pct)) / 100 : 0
                                    height: parent.height
                                    radius: Style.radius(1.5)
                                    color: session_row.has_context ? root.context_bar_color(session_row.modelData.context_pct) : "transparent"
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.selected = session_row.index;
                                root.focus_session(session_row.modelData.id);
                            }
                        }
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    visible: root.current_tab === 1
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: ClaudeUsageState.loading ? "Loading…" : ClaudeUsageState.error ? ClaudeUsageState.error : (ClaudeUsageState.updated > 0 ? "Claude usage · updated " + Qt.formatTime(new Date(ClaudeUsageState.updated), "HH:mm") : "Claude usage")
                        color: ClaudeUsageState.error && !ClaudeUsageState.loading ? Theme.warning : root.st.text_muted
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-2)
                        font.bold: true
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 24
                        visible: ClaudeUsageState.rows.length === 0 && !ClaudeUsageState.loading
                        text: ClaudeUsageState.error ? "" : "No usage data yet"
                        color: root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-1)
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: ClaudeUsageState.rows.length > 0
                        clip: true
                        spacing: 6
                        model: ClaudeUsageState.rows

                        delegate: Rectangle {
                            id: usage_row
                            required property var modelData

                            width: ListView.view.width
                            height: 56
                            radius: Style.radius(4)
                            color: "transparent"

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        elide: Text.ElideRight
                                        text: usage_row.modelData.label
                                        color: root.st.text_fg
                                        font.bold: true
                                        font.family: root.st.font_family
                                        font.pixelSize: root.st.fs(-1)
                                    }

                                    Text {
                                        text: usage_row.modelData.percent + "% used"
                                        color: root.context_bar_color(usage_row.modelData.percent)
                                        font.bold: true
                                        font.family: root.st.font_family
                                        font.pixelSize: root.st.fs(-2)
                                    }
                                }

                                Meter {
                                    Layout.fillWidth: true
                                    visible: root.st.segmented_levels
                                    segment_count: 40
                                    implicitHeight: Style.px(8)
                                    value: usage_row.modelData.percent / 100
                                    on_color: root.context_bar_color(usage_row.modelData.percent)
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 8
                                    visible: !root.st.segmented_levels
                                    radius: Style.radius(4)
                                    color: Theme.bg_surface

                                    Rectangle {
                                        width: parent.width * Math.max(0, Math.min(100, usage_row.modelData.percent)) / 100
                                        height: parent.height
                                        radius: Style.radius(4)
                                        color: root.context_bar_color(usage_row.modelData.percent)
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                    visible: usage_row.modelData.resets !== ""
                                    text: "resets " + usage_row.modelData.resets
                                    color: root.st.text_dim
                                    font.family: root.st.font_family
                                    font.pixelSize: root.st.fs(-3)
                                }
                            }
                        }
                    }
                }
            }

            MenuFooter {
                Layout.fillWidth: true
                text: root.help_hint
            }
        }
    }
}
