// home/quickshell/.config/quickshell/settings/sections/DisplaysSection.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"
import "../../services/DisplayLayout.js" as DisplayLayout
import ".."

RowsSection {
    id: root

    property int sel: 0
    property bool arranging: false

    readonly property var list: Displays.monitors
    readonly property var mon: root.list[root.sel] || null
    readonly property var enabled_rects: {
        const out = [];
        root.list.forEach((m, i) => {
            if (!m.disabled) out.push(Object.assign({ index: i }, DisplayLayout.rect_of(m)));
        });
        return out;
    }

    description_keys: root.arranging ? "hjkl nudge · HJKL fine · Enter done" : Displays.pending ? "Enter keep · Esc revert" : root.keys_of(root.described_row)
    footer_hint: root.arranging ? "hjkl nudge · HJKL fine · Enter done · Esc done · q close" : Displays.pending ? "j/k move · H/L change · Enter keep · Esc revert · q close" : "j/k move · H/L change · Enter list · h/Esc sections · q close"

    rows: {
        const m = root.mon;
        const out = [
            {
                label: "Monitor",
                desc: "The monitor the rows below change. The map shows how the screens are laid out.",
                values: () => root.list.map((x, i) => i),
                text: i => root.short_name(root.list[i]),
                value: () => root.sel,
                set: i => root.select(i)
            }
        ];
        if (!m) return out;
        if (!m.disabled) {
            out.push(
                {
                    label: "Resolution",
                    desc: "Applies at once, then reverts unless you keep it before the countdown ends.",
                    values: () => DisplayLayout.resolutions(root.mon),
                    text: v => v,
                    value: () => root.mon.width + "x" + root.mon.height,
                    set: v => root.set_mode(v)
                },
                {
                    label: "Refresh rate",
                    desc: "Refresh rate for the current resolution. Applies at once, then asks to keep it.",
                    values: () => DisplayLayout.refreshes(root.mon),
                    text: v => v + " Hz",
                    value: () => root.mon.refresh,
                    set: v => root.patch({ mode: DisplayLayout.mode_string(root.mon.width, root.mon.height, v) })
                },
                {
                    label: "Scale",
                    desc: "Interface scale for this monitor. Larger makes text and windows bigger.",
                    values: () => DisplayLayout.scales.indexOf(root.mon.scale) >= 0 ? DisplayLayout.scales : DisplayLayout.scales.concat([root.mon.scale]).sort((a, b) => a - b),
                    text: v => String(v),
                    value: () => root.mon.scale,
                    set: v => root.patch({ scale: v })
                },
                {
                    label: "Orientation",
                    desc: "Rotate or flip this monitor's picture.",
                    values: () => root.mon.transform > 3 ? DisplayLayout.rotations.concat([root.mon.transform]) : DisplayLayout.rotations,
                    text: v => DisplayLayout.transform_text(v),
                    value: () => root.mon.transform,
                    set: v => root.patch({ transform: v })
                },
                {
                    label: "Position",
                    desc: "Where this screen sits next to the others. You can also drag it on the map.",
                    keys: "H/L or Enter arrange",
                    values: () => ["arrange"],
                    text: v => root.arranging ? "hjkl to nudge" : root.mon.x + ", " + root.mon.y,
                    value: () => "arrange",
                    set: v => root.arranging = !root.arranging
                }
            );
        }
        out.push({
            label: "Enabled",
            desc: "Turn this monitor on or off. The last enabled monitor cannot be turned off.",
            values: () => ["on", "off"],
            text: v => v,
            value: () => root.mon.disabled ? "off" : "on",
            set: v => root.set_enabled(v === "on")
        });
        return out;
    }

    function short_name(m) {
        if (!m) return "";
        return m.model !== "" ? m.name + " · " + m.model : m.name;
    }

    function select(i) {
        root.sel = i;
        root.arranging = false;
    }

    function patch(fields) {
        const m = root.mon;
        if (!m) return;
        const change = {};
        change[m.name] = DisplayLayout.spec_with(m, fields);
        Displays.stage(change);
    }

    function set_mode(res) {
        const mode = DisplayLayout.mode_for(root.mon, res);
        if (mode) root.patch({ mode: mode });
    }

    function set_enabled(on) {
        const m = root.mon;
        if (!m) return;
        if (!on && Displays.enabled_count <= 1) {
            Displays.say("Cannot disable the last monitor");
            return;
        }
        const change = {};
        change[m.name] = on ? DisplayLayout.spec_with(m, {}) : { disabled: true };
        Displays.stage(change);
    }

    function move_to(index, x, y) {
        const m = root.list[index];
        if (!m) return;
        const change = {};
        change[m.name] = DisplayLayout.spec_with(m, { position: x + "x" + y });
        Displays.stage(change);
    }

    function nudge(dir, fine) {
        const at = root.enabled_rects.findIndex(r => r.index === root.sel);
        if (at < 0) return;
        const others = root.enabled_rects.filter(r => r.index !== root.sel);
        const next = DisplayLayout.nudge(root.enabled_rects[at], others, dir, fine);
        if (next) root.move_to(root.sel, next.x, next.y);
    }

    onFirst_key: event => {
        const shift = !!(event.modifiers & Qt.ShiftModifier);
        const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
        if (root.arranging) {
            const dirs = { [Qt.Key_H]: "h", [Qt.Key_J]: "j", [Qt.Key_K]: "k", [Qt.Key_L]: "l" };
            if (event.key in dirs) root.nudge(dirs[event.key], shift);
            else if (enter || event.key === Qt.Key_Space || event.key === Qt.Key_Escape) root.arranging = false;
            else return;
            event.accepted = true;
            return;
        }
        if (!Displays.pending) return;
        if (event.key === Qt.Key_Escape) Displays.revert();
        else if (enter || event.key === Qt.Key_Y) Displays.keep();
        else return;
        event.accepted = true;
    }

    onListChanged: {
        if (root.sel >= root.list.length) root.sel = Math.max(0, root.list.length - 1);
        if (!root.mon || root.mon.disabled) root.arranging = false;
    }

    Component.onCompleted: Displays.refresh()

    Rectangle {
        id: banner
        visible: Displays.pending || Displays.notice !== ""
        Layout.fillWidth: true
        Layout.preferredHeight: Style.px(26)
        radius: 6
        color: Qt.alpha(Displays.pending ? root.st.text_accent : root.st.text_muted, 0.2)

        Text {
            anchors.centerIn: parent
            text: Displays.pending ? "Keep these settings? Reverting in " + Displays.seconds_left + "s" : Displays.notice
            color: root.st.text_fg
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-2)
        }
    }

    Item {
        id: map
        Layout.fillWidth: true
        Layout.preferredHeight: Style.px(150)

        readonly property var rects: root.enabled_rects
        readonly property real min_x: Math.min(...map.rects.map(r => r.x))
        readonly property real min_y: Math.min(...map.rects.map(r => r.y))
        readonly property real span_x: Math.max(1, Math.max(...map.rects.map(r => r.x + r.w)) - map.min_x)
        readonly property real span_y: Math.max(1, Math.max(...map.rects.map(r => r.y + r.h)) - map.min_y)
        readonly property real pad: 10
        readonly property real k: map.rects.length === 0 ? 1 : Math.min((map.width - 2 * map.pad) / map.span_x, (map.height - 2 * map.pad) / map.span_y)
        readonly property real off_x: (map.width - map.span_x * map.k) / 2 - map.min_x * map.k
        readonly property real off_y: (map.height - map.span_y * map.k) / 2 - map.min_y * map.k

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(root.st.text_muted, 0.4)
        }

        Repeater {
            model: map.rects

            Rectangle {
                id: tile
                required property var modelData
                readonly property bool chosen: tile.modelData.index === root.sel
                property real drag_x: 0
                property real drag_y: 0

                x: map.off_x + tile.modelData.x * map.k + tile.drag_x
                y: map.off_y + tile.modelData.y * map.k + tile.drag_y
                width: Math.max(4, tile.modelData.w * map.k)
                height: Math.max(4, tile.modelData.h * map.k)
                radius: 3
                z: tile.chosen ? 1 : 0
                color: Qt.alpha(tile.chosen ? root.st.text_accent : root.st.text_muted, tile.chosen ? 0.35 : 0.15)
                border.width: tile.chosen ? 2 : 1
                border.color: tile.chosen ? root.st.text_accent : Qt.alpha(root.st.text_muted, 0.6)

                Text {
                    anchors.centerIn: parent
                    text: (tile.modelData.index + 1) + "\n" + (root.list[tile.modelData.index] ? root.list[tile.modelData.index].name : "")
                    horizontalAlignment: Text.AlignHCenter
                    color: root.st.text_fg
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-3)
                }

                MouseArea {
                    id: grab
                    anchors.fill: parent
                    property real start_x: 0
                    property real start_y: 0

                    onPressed: mouse => {
                        root.focus_pane();
                        root.select(tile.modelData.index);
                        const p = grab.mapToItem(map, mouse.x, mouse.y);
                        grab.start_x = p.x;
                        grab.start_y = p.y;
                    }
                    onPositionChanged: mouse => {
                        if (!grab.pressed) return;
                        const p = grab.mapToItem(map, mouse.x, mouse.y);
                        tile.drag_x = p.x - grab.start_x;
                        tile.drag_y = p.y - grab.start_y;
                    }
                    onReleased: {
                        const dx = tile.drag_x / map.k;
                        const dy = tile.drag_y / map.k;
                        tile.drag_x = 0;
                        tile.drag_y = 0;
                        if (Math.abs(dx) < 2 && Math.abs(dy) < 2) return;
                        const others = root.enabled_rects.filter(r => r.index !== tile.modelData.index);
                        const rect = Object.assign({}, tile.modelData, { x: tile.modelData.x + dx, y: tile.modelData.y + dy });
                        const next = DisplayLayout.settle(rect, others);
                        if (next) root.move_to(tile.modelData.index, next.x, next.y);
                    }
                }
            }
        }
    }
}
