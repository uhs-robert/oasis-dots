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
    implicitHeight: content.implicitHeight + 24

    property var sessions: []
    property int selected: 0
    property bool stale: false
    property double last_g_ms: 0
    readonly property int content_height: 300

    readonly property var tab_names: ["Agents", "Usage"]
    property int current_tab: 0

    readonly property bool is_open: Popups.open_name === "keeptabs"
    onIs_openChanged: if (is_open) {
        root.selected = 0;
        root.refresh();
        if (root.current_tab === 1) ClaudeUsageState.refresh(false);
    }
    onSessionsChanged: selected = Math.max(0, Math.min(selected, sessions.length - 1));
    onCurrent_tabChanged: if (root.current_tab === 1) ClaudeUsageState.refresh(false);

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
        if (state === "running") return Theme.theme_primary;
        return Theme.fg_dim;
    }

    // Below 60% the primary color, 60-85% a warning, above that an error.
    function context_bar_color(pct) {
        if (pct >= 85) return Theme.error;
        if (pct >= 60) return Theme.warning;
        return Theme.theme_primary;
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

    function set_tab(i) {
        root.current_tab = Math.max(0, Math.min(root.tab_names.length - 1, i));
    }

    function step_tab(delta) {
        root.current_tab = (root.current_tab + delta + root.tab_names.length) % root.tab_names.length;
    }

    function move_selected(delta) {
        if (root.sessions.length === 0) return;
        root.selected = (root.selected + delta + root.sessions.length) % root.sessions.length;
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
        if (event.key === Qt.Key_BracketLeft) {
            root.step_tab(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_BracketRight) {
            root.step_tab(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_1) {
            root.set_tab(0);
            event.accepted = true;
        } else if (event.key === Qt.Key_2) {
            root.set_tab(1);
            event.accepted = true;
        } else if (root.current_tab === 1 && event.key === Qt.Key_R) {
            ClaudeUsageState.refresh(true);
            event.accepted = true;
        } else if (root.current_tab === 0 && event.key === Qt.Key_J) {
            root.move_selected(1);
            event.accepted = true;
        } else if (root.current_tab === 0 && event.key === Qt.Key_K) {
            root.move_selected(-1);
            event.accepted = true;
        } else if (root.current_tab === 0 && event.key === Qt.Key_G) {
            if (event.modifiers & Qt.ShiftModifier) {
                root.go_last();
            } else {
                const now_ms = Date.now();
                if (now_ms - root.last_g_ms < 500) { root.go_first(); root.last_g_ms = 0; }
                else root.last_g_ms = now_ms;
            }
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

            // --- Content: fixed height so the popup never resizes between tabs ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.content_height

                Text {
                    anchors.centerIn: parent
                    visible: root.current_tab === 0 && root.sessions.length === 0
                    text: "No agent sessions"
                    color: Theme.fg_dim
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size - 2
                }

                ListView {
                    id: session_list
                    anchors.fill: parent
                    visible: root.current_tab === 0 && root.sessions.length > 0
                    clip: true
                    spacing: 4
                    model: root.sessions
                    currentIndex: root.selected

                    delegate: Rectangle {
                        id: session_row
                        required property var modelData
                        required property int index
                        readonly property bool has_context: session_row.modelData.context_pct !== null && session_row.modelData.context_pct !== undefined

                        width: session_list.width
                        height: 46
                        radius: 4
                        color: session_row.index === root.selected ? Theme.bg_surface : "transparent"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            anchors.topMargin: 3
                            anchors.bottomMargin: 3
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: (session_row.modelData.state || "idle").toUpperCase()
                                    color: root.state_color(session_row.modelData.state)
                                    font.family: Theme.font_family
                                    font.pixelSize: Theme.popup_font_size - 2
                                    font.bold: true
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                    text: session_row.modelData.title || "Untitled"
                                    color: Theme.fg_core
                                    font.family: Theme.font_family
                                    font.pixelSize: Theme.popup_font_size - 1
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                    text: (session_row.modelData.agent || "claude") + " · " + (session_row.modelData.project || "") + " · " + (session_row.modelData.where || "") + " · " + root.age(session_row.modelData.since)
                                    color: Theme.fg_muted
                                    font.family: Theme.font_family
                                    font.pixelSize: Theme.popup_font_size - 3
                                }

                                Text {
                                    visible: session_row.has_context
                                    text: session_row.has_context ? session_row.modelData.context_pct + "% · " + root.fmt_tokens(session_row.modelData.context_used) + "/" + root.fmt_tokens(session_row.modelData.context_window) : ""
                                    color: Theme.fg_dim
                                    font.family: Theme.font_family
                                    font.pixelSize: Theme.popup_font_size - 4
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: session_row.has_context ? 3 : 0
                                visible: session_row.has_context
                                radius: 1.5
                                color: Theme.bg_surface

                                Rectangle {
                                    width: session_row.has_context ? parent.width * Math.max(0, Math.min(100, session_row.modelData.context_pct)) / 100 : 0
                                    height: parent.height
                                    radius: 1.5
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
                        color: ClaudeUsageState.error && !ClaudeUsageState.loading ? Theme.warning : Theme.fg_muted
                        font.family: Theme.font_family
                        font.pixelSize: Theme.popup_font_size - 2
                        font.bold: true
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 24
                        visible: ClaudeUsageState.rows.length === 0 && !ClaudeUsageState.loading
                        text: ClaudeUsageState.error ? "" : "No usage data yet"
                        color: Theme.fg_dim
                        font.family: Theme.font_family
                        font.pixelSize: Theme.popup_font_size - 1
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
                            radius: 4
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
                                        color: Theme.fg_core
                                        font.bold: true
                                        font.family: Theme.font_family
                                        font.pixelSize: Theme.popup_font_size - 1
                                    }

                                    Text {
                                        text: usage_row.modelData.percent + "% used"
                                        color: root.context_bar_color(usage_row.modelData.percent)
                                        font.bold: true
                                        font.family: Theme.font_family
                                        font.pixelSize: Theme.popup_font_size - 2
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 8
                                    radius: 4
                                    color: Theme.bg_surface

                                    Rectangle {
                                        width: parent.width * Math.max(0, Math.min(100, usage_row.modelData.percent)) / 100
                                        height: parent.height
                                        radius: 4
                                        color: root.context_bar_color(usage_row.modelData.percent)
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                    visible: usage_row.modelData.resets !== ""
                                    text: "resets " + usage_row.modelData.resets
                                    color: Theme.fg_dim
                                    font.family: Theme.font_family
                                    font.pixelSize: Theme.popup_font_size - 3
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.current_tab === 0
                    ? "[ ] tabs · 1-2 select · j/k move · gg/G first/last · Enter/click focus"
                    : "[ ] tabs · 1-2 select · r refresh"
                color: Theme.fg_dim
                font.family: Theme.font_family
                font.pixelSize: Theme.popup_font_size - 4
            }
        }
    }
}
