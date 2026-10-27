import QtQuick
import QtQuick.Layouts
import qs.core
import qs.features.settings
import qs.features.developer
import qs.features.audio
import qs.theme

// One ReviewerRow per code reviewer. RowsSection holds one value per row, so this is a SettingsPane of its own;
// the keys are RowsSection's (j/k, l/Space/Shift+H/L change) plus w/b or Left/Right to switch the editable column.
SettingsPane {
    id: root

    property int cursor: 0
    property int column: 0
    readonly property var reviewers: DeveloperSettings.reviewers
    readonly property var current: root.reviewers[root.cursor] || null
    readonly property var column_keys: ["local", "gate"]

    footer_hint: "j/k move · w/b column · H/L change · h/Esc sections · q close"
    search_rows: root.reviewers.map(r => r.label)
    search_cursor: root.cursor
    described: true
    description: root.describe(root.current)
    description_keys: "j/k reviewer · w/b or Left/Right column · H/L change"
    implicitHeight: col.implicitHeight

    function describe(r) {
        if (!r) return "No reviewers are listed. Add them in ~/.config/code-reviewers/reviewers.json.";
        const where = root.column === 0 ? "Local review: which repos the pre-PR review of " + r.label + " covers. Off skips it, Public runs it on public repos only, All on every repo (the diff goes to the provider)." : "Merge gate: whether merge waits for " + r.label + " on the PR. Auto waits when it is connected to the repo, Always always waits, Never does not wait.";
        const missing = r.installed ? "" : "\n\n" + r.binary + " is not installed, so its local review stays off. The merge gate is GitHub-side and still applies.";
        return where + missing;
    }

    function change(delta) {
        const r = root.current;
        if (!r) return;
        const key = root.column_keys[root.column];
        if (key === "local" && !r.installed) return;
        DeveloperSettings.set(r.name, key, DeveloperSettings.step(key, r[key], delta));
        ThemeAudio.play("confirm");
    }

    function search_select(index) {
        root.cursor = index;
    }

    function jump(delta) {
        root.cursor = delta < 0 ? 0 : Math.max(0, root.reviewers.length - 1);
    }

    onCursorChanged: if (root.live) ThemeAudio.play("cursor")
    onLiveChanged: if (root.live) DeveloperSettings.probe()
    Component.onCompleted: DeveloperSettings.probe()

    Keys.onPressed: event => {
        if (root.picking) return;
        if (event.modifiers & Qt.ControlModifier) return;
        const shift = !!(event.modifiers & Qt.ShiftModifier);
        const count = root.reviewers.length;
        if (event.key === Qt.Key_J) root.cursor = root.wrap_index(root.cursor, 1, count);
        else if (event.key === Qt.Key_K) root.cursor = root.wrap_index(root.cursor, -1, count);
        else if (event.key === Qt.Key_W || event.key === Qt.Key_Right) root.column = 1;
        else if (event.key === Qt.Key_B || event.key === Qt.Key_Left) root.column = 0;
        // Plain h is left for the popup, which goes back to the sidebar.
        else if (event.key === Qt.Key_H && shift) root.change(-1);
        else if (event.key === Qt.Key_L || event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.change(1);
        else return;
        event.accepted = true;
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 4

        ReviewerRow {
            header: true
        }

        Repeater {
            model: root.reviewers

            ReviewerRow {
                id: row
                required property int index
                required property var modelData

                selected: root.live && row.index === root.cursor
                column: root.column
                label: row.modelData.label
                installed_text: row.modelData.installed ? "yes" : "no"
                local_text: row.modelData.local
                gate_text: row.modelData.gate
                local_editable: row.modelData.installed
                onStepped: (column, delta) => {
                    root.focus_pane();
                    root.cursor = row.index;
                    root.column = column;
                    root.change(delta);
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 6
            text: "Add reviewers in ~/.config/code-reviewers/reviewers.json; per-repo overrides go in .claude/reviewers.json."
            wrapMode: Text.WordWrap
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-2)
        }
    }
}
