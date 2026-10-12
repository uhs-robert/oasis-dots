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
        ? "Tab tabs · 1-2 select · " + (root.view_moves_across ? "h/j/k/l move" : "j/k move") + " · gg/G first/last · Enter/click focus"
        : "Tab tabs · 1-2 select · r refresh"

    property var sessions: []
    property int selected: 0
    property bool stale: false
    property int pick_exit: 0
    readonly property int content_height: Style.px(300)

    tabs: ["Agents", "Usage"]
    jumps_enabled: root.current_tab === 0
    cursor_state: root.selected

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
        root.ensure_visible(index);
    }
    onJump_first: root.go_first()
    onJump_last: root.go_last()

    // Views a layout draws itself, as keeptabs/<prefix><View>.qml for Agents or Usage; any other view falls back
    // to the shared one. The blank lines keep each layout's line its own hunk, so style PRs that each flip one line
    // merge without conflicts.
    readonly property var layout_views: ({
        battle: { prefix: "Party", views: ["Agents", "Usage"] },

        hero: { prefix: "Activities", views: [] },

        hev: { prefix: "Weapon", views: [] },

        lsp: { prefix: "Trouble", views: [] },

        memcard: { prefix: "MemCard", views: [] },

        mode7: { prefix: "Ff6", views: [] },

        oasis: { prefix: "Caravan", views: [] },

        pokedex: { prefix: "Pkmn", views: [] },

        ring: { prefix: "Roster", views: [] },

        scan: { prefix: "Logbook", views: [] },

        scope: { prefix: "Target", views: [] },

        status: { prefix: "Ff7Menu", views: [] },

        towers: { prefix: "Browser", views: [] },

        watch: { prefix: "Mission", views: [] },

        weatherstar: { prefix: "Observations", views: [] },

        wttr: { prefix: "Htop", views: [] }
    })

    function view_url(view, shared) {
        const own = root.layout_views[Style.keeptabs_layout];
        const file = own && own.views.includes(view) ? own.prefix + view : shared;
        return Qt.resolvedUrl("keeptabs/" + file + ".qml");
    }

    // The shared MenuFooter is hidden only while the visible tab's view draws its own key help.
    readonly property bool view_draws_footer: {
        const loader = root.current_tab === 0 ? agents_loader : usage_loader;
        return loader.item ? loader.item.draws_footer === true : false;
    }

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
        onExited: code => {
            root.pick_exit = code;
            if (root.stale) {
                root.stale = false;
                root.refresh();
            }
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

    function ensure_visible(index) {
        if (agents_loader.item) agents_loader.item.ensure_visible(index);
    }

    function focus_session(id) {
        ThemeAudio.play("confirm");
        Quickshell.execDetached(["sh", "-c", "exec ~/.local/bin/keeptabs-pick --focus \"$1\"", "sh", id]);
        Popups.close();
    }

    // Grids and columns lay sessions out across as well as down, so their view picks the target of each move;
    // the plain list only steps down and up, wrapping.
    readonly property bool view_moves_across: agents_loader.item ? agents_loader.item.moves_across === true : false

    function move_selected(dx, dy) {
        if (root.sessions.length === 0) return;
        const item = agents_loader.item;
        const target = item && typeof item.nav_target === "function"
            ? item.nav_target(root.selected, dx, dy)
            : dx === 0 ? root.wrap_index(root.selected, dy, 0, root.sessions.length) : root.selected;
        root.selected = Math.max(0, Math.min(root.sessions.length - 1, target));
        root.ensure_visible(root.selected);
    }

    function go_first() {
        if (root.sessions.length === 0) return;
        root.selected = 0;
        root.ensure_visible(root.selected);
    }

    function go_last() {
        if (root.sessions.length === 0) return;
        root.selected = root.sessions.length - 1;
        root.ensure_visible(root.selected);
    }

    function handle_key(event) {
        const before = root.cursor_key();
        if (root.current_tab === 1 && event.key === Qt.Key_R) {
            ClaudeUsageState.refresh(true);
            ThemeAudio.play("confirm");
            event.accepted = true;
        } else if (root.current_tab === 0 && (event.key === Qt.Key_J || event.key === Qt.Key_K)) {
            root.move_selected(0, event.key === Qt.Key_J ? 1 : -1);
            root.play_if_moved(before);
            event.accepted = true;
        } else if (root.current_tab === 0 && root.view_moves_across && !(event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_H || event.key === Qt.Key_L)) {
            root.move_selected(event.key === Qt.Key_L ? 1 : -1, 0);
            root.play_if_moved(before);
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
                onPicked: index => {
                    root.set_tab(index);
                    ThemeAudio.play("cursor");
                }
            }

            // --- Content: fixed height so the popup never resizes between tabs ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.content_height

                Loader {
                    id: agents_loader
                    anchors.fill: parent
                    visible: root.current_tab === 0
                    readonly property url url: root.view_url("Agents", "AgentsView")
                    onUrlChanged: agents_loader.load()
                    Component.onCompleted: agents_loader.load()

                    function load() {
                        agents_loader.setSource(agents_loader.url, {
                            sessions: Qt.binding(() => root.sessions),
                            selected: Qt.binding(() => root.selected),
                            pick_exit: Qt.binding(() => root.pick_exit),
                            st: Qt.binding(() => root.st),
                            on_select: function (i) { root.selected = i; },
                            on_activate: function (id) { root.focus_session(id); }
                        });
                    }
                }

                Loader {
                    id: usage_loader
                    anchors.fill: parent
                    visible: root.current_tab === 1
                    readonly property url url: root.view_url("Usage", "UsageView")
                    onUrlChanged: usage_loader.load()
                    Component.onCompleted: usage_loader.load()

                    function load() {
                        usage_loader.setSource(usage_loader.url, {
                            st: Qt.binding(() => root.st)
                        });
                    }
                }
            }

            MenuFooter {
                Layout.fillWidth: true
                visible: !root.view_draws_footer
                text: root.help_hint
            }
        }
    }
}
