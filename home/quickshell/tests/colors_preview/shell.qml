import QtQuick
import Quickshell
import Quickshell.Io
import qs.theme
import qs.features.settings
import qs.features.settings.sections

// Harness for run.sh: opens the Palette list in ColorsSection beside a SettingsPanel at several sizes and writes one
// PASS or FAIL line per size to $RESULT. FAIL when the preview card is not in the panel, intersects the list or the
// pane or moves when the list opens, or (no preview) when the help card does not get the whole panel.
ShellRoot {
    id: root

    // [pane width, pane height, kind, panel width, panel height, stacked]; stacked puts the panel under the pane.
    readonly property var sizes: [[860, 1100, "colors", 520, 1100, false], [500, 1100, "colors", 300, 1100, false], [1000, 900, "colors", 1000, 270, true], [700, 700, "colors", 700, 210, true], [860, 1100, "plain", 520, 1100, false], [1000, 700, "plain", 1000, 210, true]]
    property int at: 0
    property string report: ""

    Component.onCompleted: Qt.callLater(root.check)

    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children) {
            const hit = root.find(child, name);
            if (hit) return hit;
        }
        return null;
    }

    function within(item, ancestor) {
        for (let p = item; p; p = p.parent) if (p === ancestor) return true;
        return false;
    }

    function overlaps(a, b) {
        return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
    }

    function box(item) {
        const p = item.mapToItem(stage, 0, 0);
        // The list draws its rows past its own height, so its extent is rebuilt from what it shows.
        const h = item.objectName === "picker" ? item.chrome_height + Math.min(item.window_size, item.results.length) * (item.row_height + item.spacing) : item.height;
        return { x: p.x, y: p.y, w: item.width, h: h };
    }

    // Sets up size `at` with the list closed; the closed measurements are taken once the layout stops moving.
    function check() {
        const size = root.sizes[root.at];
        const plain = size[2] === "plain";
        // An inactive loader unloads its section, so the other one's preview leaves the panel.
        holder.active = !plain;
        bare.active = plain;
        const active = plain ? bare : holder;
        active.width = size[0];
        active.height = size[1];
        panel.stacked = size[5];
        panel.width = size[3];
        panel.height = size[4];
        panel.x = size[5] ? 0 : size[0] + 24;
        panel.y = size[5] ? size[1] + 24 : 0;
        root.phase = "closed";
        root.last_layout = "";
        root.waited = 0;
        settle.restart();
    }

    property string phase: "closed"
    property string last_layout: ""
    property int waited: 0
    property var closed_card: null
    property string pending_detail: ""

    function section_now() {
        return (root.sizes[root.at][2] === "plain" ? bare : holder).item;
    }

    // What the layout looks like now; two equal snapshots in a row mean it has settled.
    function layout_snapshot() {
        const section = root.section_now();
        const card = root.find(panel, "card");
        const list = root.find(section, "picker");
        return JSON.stringify([card ? root.box(card) : null, list && list.visible ? root.box(list) : null, panel.width, panel.height]);
    }

    function tick() {
        const section = root.section_now();
        const now = root.layout_snapshot();
        const open = root.phase === "open";
        const list = root.find(section, "picker");
        // An open list is ready when the section reports it and the list has drawn its rows.
        const ready = open ? section.picking && list && list.visible && list.results.length > 0 : !section.picking;
        root.waited++;
        if (!(ready && now === root.last_layout) && root.waited < 60) {
            root.last_layout = now;
            settle.restart();
            return;
        }
        if (open) root.judge();
        else root.measure_closed();
    }

    function measure_closed() {
        const card = root.find(panel, "card");
        root.closed_card = card ? root.box(card) : null;
        const section = root.section_now();
        const labels = [];
        for (let i = 0; i < 30; i++) labels.push("palette " + i);
        root.phase = "open";
        root.last_layout = "";
        root.waited = 0;
        section.open_list("Palette", labels, labels, labels[0], v => {});
        settle.restart();
    }

    function judge() {
        const size = root.sizes[root.at];
        const plain = size[2] === "plain";
        const section = root.section_now();
        const list = root.find(section, "picker");
        const a = root.box(list);
        let bad = !section.picking;
        let detail = " list " + JSON.stringify(a);
        if (plain) {
            // No preview: the list still fills the pane, and the help card (hidden while the list is open) gets the whole panel once closed.
            bad = bad || a.h <= list.default_height + list.row_height;
            section.hide_picker();
            root.pending_detail = detail;
            root.phase = "after";
            root.waited = 0;
            panel_settle.restart();
            return;
        }
        const card = root.find(panel, "card");
        const b = card ? root.box(card) : null;
        const panel_box = { x: panel.x, y: panel.y, w: panel.width, h: panel.height };
        bad = bad || !card || !card.visible || !root.within(card, panel) || b.w <= 0 || b.h <= 0 || root.overlaps(a, b)
            || b.x < panel_box.x || b.y < panel_box.y || b.x + b.w > panel_box.x + panel_box.w + 1 || b.y + b.h > panel_box.y + panel_box.h + 1;
        // Opening the list must not move the card the owner browses palettes against.
        const moved = JSON.stringify(b) !== JSON.stringify(root.closed_card);
        detail += " card " + JSON.stringify(b) + (moved ? " MOVED from " + JSON.stringify(root.closed_card) : "");
        section.hide_picker();
        root.finish(bad || moved, detail);
    }

    function judge_closed() {
        const help = root.find(panel, "help");
        const bad = panel.has_preview || Math.abs(help.height - panel.height) > 1 || help.width !== panel.width || help.height <= 0;
        root.finish(bad, root.pending_detail + " help " + help.width + "x" + help.height + " panel " + panel.width + "x" + panel.height);
    }

    function finish(bad, detail) {
        const size = root.sizes[root.at];
        root.report += (bad ? "FAIL" : "PASS") + " " + size[2] + " " + size[0] + "x" + size[1] + (size[5] ? " stacked" : "") + detail + "\n";
        root.at++;
        if (root.at < root.sizes.length) root.check();
        else out.setText(root.report);
    }

    Timer {
        id: settle
        interval: 50
        onTriggered: root.tick()
    }

    Timer {
        id: panel_settle
        interval: 200
        onTriggered: root.judge_closed()
    }

    // Stands in for SettingsPopup: the hosts a pane docks its help and preview into.
    QtObject {
        id: fake_popup
        readonly property var st: Style
        readonly property Item description_host: panel.help_host
        readonly property Item preview_host: panel.preview_host
        readonly property bool is_open: true
        readonly property bool in_pane: true
        function enter_pane() {
        }
    }

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 2000
        implicitHeight: 2600

        Item {
            id: stage
            anchors.fill: parent

            Loader {
                id: holder
                active: false
                sourceComponent: ColorsSection { popup: fake_popup }
            }

            Loader {
                id: bare
                active: false
                sourceComponent: RowsSection {
                    popup: fake_popup
                    rows: [{ label: "Row", desc: "d", values: () => ["a", "b"], text: v => v, value: () => "a", set: v => {} }]
                }
            }

            SettingsPanel {
                id: panel
            }
        }
    }

    FileView {
        id: out
        path: Quickshell.env("RESULT")
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }
}
