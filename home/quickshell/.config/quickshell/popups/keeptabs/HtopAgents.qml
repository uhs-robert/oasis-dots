// home/quickshell/.config/quickshell/popups/keeptabs/HtopAgents.qml
import QtQuick
import "../../theme"
import "../weather/WttrArt.js" as WttrArt
import "KeeptabsFormat.js" as Fmt

// The Agents tab as htop's process list: one monospace line per session, the selected one a full-width bar,
// with htop's F-key strip as the footer. Contract as in AgentsView.
Item {
    id: root

    property var sessions: []
    property int selected: 0
    property int pick_exit: 0
    property var st: Style
    property var on_select: function (i) {}
    property var on_activate: function (id) {}
    // The strip below replaces the shared footer, including the search query line it would show.
    property bool draws_footer: true

    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_primary, text_dim: root.st.text_dim })
    readonly property int text_px: root.st.fs(-3)
    // Reading metrics.font makes the advance rebind once the family and size land.
    readonly property real glyph_w: metrics.font.pixelSize > 0 ? Math.max(1, metrics.advanceWidth("M")) : 1
    readonly property real lh: Math.max(1, Math.floor(metrics.height))
    readonly property int cols: Math.floor(root.width / root.glyph_w)
    // "  PID S CTX%  TOKENS  TIME+ " is 26 characters; the command gets the rest of the line.
    readonly property int command_cols: Math.max(0, root.cols - 26)
    readonly property string inverse: String(Style.tab_active_fg)
    readonly property var state_letters: ({ running: "R", idle: "S", waiting: "D", done: "Z" })
    readonly property var keys: [["/", "Search"], ["Enter", "Focus"], ["Tab", "Usage"], ["gg/G", "Ends"], ["q", "Close"]]

    readonly property var search_popup: {
        for (let p = root.parent; p; p = p.parent) {
            if (p.search_popup !== undefined) return p.search_popup;
        }
        return null;
    }
    readonly property bool searching: !!root.search_popup && root.search_popup.search_shown

    function ensure_visible(i) {
        session_list.positionViewAtIndex(i, ListView.Contain);
    }

    function pad_left(value, width) {
        const s = String(value);
        return s.length >= width ? s.slice(0, width) : " ".repeat(width - s.length) + s;
    }

    function ellipsize(s, width) {
        if (s.length <= width) return s;
        return width <= 0 ? "" : s.slice(0, width - 1) + "…";
    }

    // Project and title keep their room first; agent and where fill what is left and elide before them.
    function command_runs(session, selected_row) {
        const project = session.project ? session.project + "/" : "";
        const head = root.ellipsize(project + (session.title || "Untitled"), root.command_cols);
        const room = root.command_cols - head.length;
        const tail = root.ellipsize(" " + [session.agent || "claude", session.where || ""].join(" ").trim(), room);
        const cut = Math.min(project.length, head.length);
        const dim = selected_row ? root.inverse : String(root.st.text_dim);
        const bright = selected_row ? root.inverse : String(Style.text_strong);
        return [[head.slice(0, cut), dim], [head.slice(cut), bright], [room >= 4 ? tail : "", dim]];
    }

    function row_text(session, i, selected_row) {
        const has_context = session.context_pct !== null && session.context_pct !== undefined;
        const plain = selected_row ? root.inverse : String(root.st.text_fg);
        const state = session.state || "idle";
        const state_color = selected_row ? root.inverse : String(Fmt.state_color(state, root.colors));
        const context_color = selected_row ? root.inverse : has_context ? String(Fmt.context_bar_color(session.context_pct, root.colors)) : String(root.st.text_dim);
        return WttrArt.runs([
            [root.pad_left(session.pid || i + 1, 5) + " ", plain],
            [(root.state_letters[state] || "S") + " ", state_color],
            [root.pad_left(has_context ? session.context_pct + "%" : "-", 4) + " ", context_color],
            [root.pad_left(has_context ? Fmt.fmt_tokens(session.context_used) : "-", 6) + " ", plain],
            [root.pad_left(Fmt.age(session.since), 5) + " ", plain]
        ].concat(root.command_runs(session, selected_row)));
    }

    FontMetrics {
        id: metrics
        font.family: root.st.mono_font
        font.pixelSize: root.text_px
    }

    Rectangle {
        id: header
        width: parent.width
        height: root.lh
        color: root.st.text_primary

        Text {
            height: root.lh
            text: WttrArt.runs([[root.pad_left("PID", 5) + " S " + root.pad_left("CTX%", 4) + " " + root.pad_left("TOKENS", 6) + " " + root.pad_left("TIME+", 5) + " Command", root.inverse]])
            textFormat: Text.StyledText
            color: Style.tab_active_fg
            font.family: root.st.mono_font
            font.pixelSize: root.text_px
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.sessions.length === 0
        text: root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed"
        color: root.st.text_dim
        font.family: root.st.mono_font
        font.pixelSize: root.text_px
    }

    ListView {
        id: session_list
        y: root.lh
        width: parent.width
        height: Math.max(0, root.height - 2 * root.lh)
        visible: root.sessions.length > 0
        clip: true
        model: root.sessions
        currentIndex: root.selected

        delegate: Item {
            id: process_row
            required property var modelData
            required property int index
            readonly property bool is_selected: process_row.index === root.selected

            width: session_list.width
            height: root.lh

            Rectangle {
                anchors.fill: parent
                visible: process_row.is_selected
                color: Style.tab_active_bg
            }

            Text {
                height: root.lh
                width: parent.width
                clip: true
                text: root.row_text(process_row.modelData, process_row.index, process_row.is_selected)
                textFormat: Text.StyledText
                color: root.st.text_fg
                font.family: root.st.mono_font
                font.pixelSize: root.text_px
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.on_select(process_row.index);
                    root.on_activate(process_row.modelData.id);
                }
            }
        }
    }

    Row {
        y: root.height - root.lh
        width: parent.width
        height: root.lh
        clip: true
        visible: !root.searching

        Repeater {
            model: root.keys

            Row {
                id: key_cell
                required property var modelData

                Rectangle {
                    width: key_text.implicitWidth
                    height: root.lh
                    color: Style.tab_active_bg

                    Text {
                        id: key_text
                        text: key_cell.modelData[0]
                        color: Style.tab_active_fg
                        font.family: root.st.mono_font
                        font.pixelSize: root.text_px
                    }
                }

                Text {
                    text: key_cell.modelData[1] + " "
                    color: root.st.text_fg
                    font.family: root.st.mono_font
                    font.pixelSize: root.text_px
                }
            }
        }
    }

    Row {
        y: root.height - root.lh
        width: parent.width
        height: root.lh
        clip: true
        visible: root.searching

        Rectangle {
            width: search_key.implicitWidth
            height: root.lh
            color: Style.tab_active_bg

            Text {
                id: search_key
                text: "/Search:"
                color: Style.tab_active_fg
                font.family: root.st.mono_font
                font.pixelSize: root.text_px
            }
        }

        Text {
            readonly property int matches: root.searching ? root.search_popup.search_matches.length : 0
            readonly property int position: root.searching ? root.search_popup.search_matches.indexOf(root.search_popup.search_cursor) : -1
            text: " " + (root.searching ? root.search_popup.search_query : "") + "▏" + (matches === 0 && root.search_popup.search_query !== "" ? "  no match" : root.search_popup.search_query !== "" ? "  " + (position >= 0 ? position + 1 : "-") + "/" + matches : "")
            color: root.st.text_fg
            font.family: root.st.mono_font
            font.pixelSize: root.text_px
        }
    }
}
