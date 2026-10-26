import QtQuick
import Quickshell
import Quickshell.Io
import qs.features.settings.sections

// Harness for run.sh: opens the Palette list in ColorsSection at several pane sizes and writes one PASS or FAIL line
// per size to $RESULT, FAIL when the list and the preview card intersect.
ShellRoot {
    id: root

    readonly property var sizes: [[1900, 1100], [1000, 1100], [700, 1100], [500, 900]]
    property int at: 0
    property string report: ""

    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children) {
            const hit = root.find(child, name);
            if (hit) return hit;
        }
        return null;
    }

    function overlaps(a, b) {
        return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
    }

    function box(item, section) {
        const p = item.mapToItem(section, 0, 0);
        // The list draws its rows past its own height, so its extent is rebuilt from what it shows.
        const h = item.objectName === "picker" ? item.chrome_height + Math.min(item.window_size, item.results.length) * (item.row_height + item.spacing) : item.height;
        return { x: p.x, y: p.y, w: item.width, h: h };
    }

    function check() {
        const size = root.sizes[root.at];
        const section = holder.item;
        holder.width = size[0];
        holder.height = size[1];
        const labels = [];
        for (let i = 0; i < 30; i++) labels.push("palette " + i);
        section.open_list("Palette", labels, labels, labels[0], v => {});
        settle.restart();
    }

    function judge() {
        const size = root.sizes[root.at];
        const section = holder.item;
        const list = root.find(section, "picker");
        const card = root.find(section, "card");
        const a = root.box(list, section);
        const b = root.box(card, section);
        const bad = a.w <= 0 || b.w <= 0 || root.overlaps(a, b);
        root.report += (bad ? "FAIL" : "PASS") + " " + size[0] + "x" + size[1] + " list " + JSON.stringify(a) + " card " + JSON.stringify(b) + "\n";
        section.hide_picker();
        root.at++;
        if (root.at < root.sizes.length) root.check();
        else out.setText(root.report);
    }

    Timer {
        id: settle
        interval: 400
        onTriggered: root.judge()
    }

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 2000
        implicitHeight: 1300

        Item {
            anchors.fill: parent

            Loader {
                id: holder
                sourceComponent: ColorsSection {}
                onLoaded: Qt.callLater(root.check)
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
