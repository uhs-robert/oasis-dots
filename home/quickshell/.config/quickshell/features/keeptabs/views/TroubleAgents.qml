import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.features.popups
import "KeeptabsFormat.js" as Fmt

// The Agents tab as a Trouble.nvim list: a fold per state (the given waiting-first order is kept, so a fold
// is a run of equal states), one diagnostic line per session. Folds are rows of the list but never selectable:
// `selected` indexes sessions and row_of maps it to its row. Contract as in AgentsView.
Item {
    id: root

    property var sessions: []
    property int selected: 0
    property int pick_exit: 0
    property var st: Style
    property var on_select: function (i) {}
    property var on_activate: function (id) {}
    property bool draws_footer: false

    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_primary, text_dim: root.st.text_dim })
    readonly property var spinner_frames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    readonly property var state_titles: ({ waiting: "Waiting", done: "Done", running: "Running", idle: "Idle" })
    readonly property var state_signs: ({ waiting: "E", done: "I", idle: "H" })
    property int spinner_frame: 0

    readonly property var layout_rows: {
        const rows = [];
        const row_of = [];
        let header = null;
        for (let i = 0; i < root.sessions.length; i++) {
            const state = root.sessions[i].state || "idle";
            if (!header || header.state !== state) {
                header = { kind: "header", state: state, count: 0, session: -1 };
                rows.push(header);
            }
            header.count++;
            row_of.push(rows.length);
            rows.push({ kind: "item", state: state, count: 0, session: i });
        }
        return { rows: rows, row_of: row_of };
    }
    readonly property var current: root.sessions[root.selected] || null
    readonly property bool animating: root.visible && Popups.open_name === "keeptabs"

    function ensure_visible(i) {
        const row = root.layout_rows.row_of[i];
        if (row === undefined) return;
        // The fold header scrolls in with its first session.
        const first_in_fold = row > 0 && root.layout_rows.rows[row - 1].kind === "header";
        // Header first, then the item, so a header below the viewport does not push the item out of view.
        if (first_in_fold) session_list.positionViewAtIndex(row - 1, ListView.Contain);
        session_list.positionViewAtIndex(row, ListView.Contain);
    }

    function escape_markup(text) {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;");
    }

    onSelectedChanged: root.ensure_visible(root.selected)

    Timer {
        interval: 90
        repeat: true
        running: root.animating && root.sessions.some(s => s.state === "running")
        onTriggered: root.spinner_frame = (root.spinner_frame + 1) % root.spinner_frames.length
    }

    Text {
        anchors.centerIn: parent
        visible: root.sessions.length === 0
        text: root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed"
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    ListView {
        id: session_list
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: detail.top
        anchors.bottomMargin: 4
        visible: root.sessions.length > 0
        clip: true
        model: root.layout_rows.rows
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: line
            required property var modelData
            required property int index

            readonly property bool is_header: line.modelData.kind === "header"
            readonly property var session: line.is_header ? null : root.sessions[line.modelData.session]
            readonly property bool is_selected: !line.is_header && line.modelData.session === root.selected
            readonly property bool is_running: line.modelData.state === "running"
            readonly property bool has_context: !!line.session && line.session.context_pct !== null && line.session.context_pct !== undefined
            readonly property bool context_high: line.has_context && line.session.context_pct >= 85
            readonly property color accent: Fmt.state_color(line.modelData.state, root.colors)
            readonly property color sign_color: line.modelData.state === "waiting" ? Style.pal.error : line.context_high ? Style.pal.warning : line.modelData.state === "done" ? Style.pal.info : line.modelData.state === "idle" ? Style.pal.hint : root.st.text_primary

            width: session_list.width
            height: line.is_header ? Style.px(26) : Style.px(23)

            Rectangle {
                visible: line.is_selected
                anchors.fill: parent
                color: Style.selection_bg
            }

            Text {
                visible: line.is_selected
                anchors.verticalCenter: parent.verticalCenter
                text: "▎"
                color: Style.caret_color
                font.family: root.st.mono_font
                font.pixelSize: root.st.fs(-1)
            }

            // Fold header, styled like an nvim-notify title line: glyph and name in the accent, rule under it.
            RowLayout {
                visible: line.is_header
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                spacing: 7

                Text {
                    text: "\u{f078}"
                    color: line.accent
                    font.family: Style.font_family
                    font.pixelSize: root.st.fs(-3)
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: (root.state_titles[line.modelData.state] || line.modelData.state) + " (" + line.modelData.count + ")"
                    color: line.accent
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-3)
                    font.bold: true
                }
            }

            Rectangle {
                visible: line.is_header
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Style.pal.bg_surface
            }

            RowLayout {
                visible: !line.is_header
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 6
                spacing: 6

                Text {
                    Layout.preferredWidth: Style.px(12)
                    horizontalAlignment: Text.AlignHCenter
                    text: line.is_running ? root.spinner_frames[root.spinner_frame] : (root.state_signs[line.modelData.state] || "H")
                    color: line.sign_color
                    font.family: root.st.mono_font
                    font.pixelSize: root.st.fs(-2)
                    font.bold: true
                }

                // Title and the dim [where] tail share one text so a long title pushes the tail out first.
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: line.session ? root.escape_markup(line.session.title || "Untitled") + (line.session.where ? " <font color=\"" + Qt.alpha(root.st.text_dim, 1) + "\">[" + root.escape_markup(line.session.where) + "]</font>" : "") : ""
                    color: line.is_selected ? root.st.text_strong : root.st.text_fg
                    font.family: root.st.mono_font
                    font.pixelSize: root.st.fs(-2)
                }

                Rectangle {
                    visible: line.has_context
                    implicitWidth: hint_text.implicitWidth + 6
                    implicitHeight: hint_text.implicitHeight
                    radius: 2
                    color: Qt.alpha(root.st.text_dim, line.is_selected ? 0.18 : 0.1)

                    Text {
                        id: hint_text
                        anchors.centerIn: parent
                        text: line.has_context ? "ctx:" + line.session.context_pct + "%" : ""
                        color: line.has_context ? Fmt.context_bar_color(line.session.context_pct, root.colors) : root.st.text_dim
                        font.family: root.st.mono_font
                        font.pixelSize: root.st.fs(-4)
                    }
                }

                Text {
                    Layout.preferredWidth: Math.ceil(age_metrics.advanceWidth("99m"))
                    horizontalAlignment: Text.AlignRight
                    text: line.session ? Fmt.age(line.session.since) : ""
                    color: root.st.text_muted
                    font.family: root.st.mono_font
                    font.pixelSize: root.st.fs(-4)
                }
            }

            MouseArea {
                enabled: !line.is_header
                anchors.fill: parent
                onClicked: {
                    root.on_select(line.modelData.session);
                    root.on_activate(line.session.id);
                }
            }
        }
    }

    FontMetrics {
        id: age_metrics
        font.family: root.st.mono_font
        font.pixelSize: root.st.fs(-4)
    }

    // The selected session in full, like a Trouble preview: the title wrapped, then agent, project, where and tokens.
    Item {
        id: detail
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.current !== null
        height: root.current ? detail_column.implicitHeight + 8 : 0

        Rectangle {
            width: parent.width
            height: 1
            color: Style.pal.bg_surface
        }

        ColumnLayout {
            id: detail_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 1

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: root.current ? (root.current.title || "Untitled") : ""
                color: root.st.text_fg
                font.family: root.st.mono_font
                font.pixelSize: root.st.fs(-3)
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: root.current ? (root.current.agent || "claude") + " · " + (root.current.project || "") + (root.current.where ? " · " + root.current.where : "") + (root.current.context_pct !== null && root.current.context_pct !== undefined ? " · " + root.current.context_pct + "% · " + Fmt.fmt_tokens(root.current.context_used) + "/" + Fmt.fmt_tokens(root.current.context_window) : "") : ""
                color: root.st.text_dim
                font.family: root.st.mono_font
                font.pixelSize: root.st.fs(-4)
            }
        }
    }
}
