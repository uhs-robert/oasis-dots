// home/quickshell/.config/quickshell/bar/modules/Keeptabs.qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../theme"
import "../../services"
import "../../components"

Item {
    id: root

    property bool compact: false
    property string screen_name: ""
    property Item island: null
    property color island_color: Theme.bg_core

    readonly property bool shown: KeeptabsState.available
    readonly property string tooltip_text: {
        const usage = ClaudeUsageState.rows.map(r => r.label + ": " + r.percent + "%").join("\n");
        return KeeptabsState.tooltip.replace(/\t/g, "  ") + (usage ? "\n\n" + usage : "");
    }
    visible: shown
    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    onIslandChanged: if (root.island) Popups.register_default("keeptabs", root.island, root.island_color, root.screen_name, root)
    Component.onDestruction: Popups.unregister("keeptabs", root.screen_name, root)

    // The animated glyph's centre, colour and free slot; delegates are rebuilt on every stream line, so they report it here.
    property var done_anchor: null
    property var wait_anchor: null
    readonly property bool wait_hides_glyph: wait_loader.item ? wait_loader.item.hides_glyph : false
    // Half the island's module spacing, which is also its edge padding.
    readonly property real edge_room: 8

    function play_wait(nudge) {
        if (!root.groups.some(g => g.glyph === KeeptabsState.wait_glyph)) return;
        wait_loader.nudge = nudge;
        wait_loader.active = false;
        wait_loader.active = true;
    }

    function play_done(nudge) {
        if (!root.groups.some(g => g.glyph === KeeptabsState.done_glyph)) return;
        pulse_loader.nudge = nudge;
        pulse_loader.active = false;
        pulse_loader.active = true;
    }

    // Nudges replay only on AC; the timer never runs while nothing waits or is done.
    function sync_nudge() {
        if ((KeeptabsState.waiting_count > 0 || KeeptabsState.done_count > 0) && Power.on_ac) {
            if (!nudge_timer.running) nudge_timer.start();
        } else {
            nudge_timer.stop();
        }
        if (KeeptabsState.waiting_count === 0) wait_loader.active = false;
        if (KeeptabsState.done_count === 0) pulse_loader.active = false;
    }

    // Restarts the shared cadence so the next nudge of the kind that just played is 10s away.
    function rephase(tick) {
        if (!nudge_timer.running) return;
        nudge_timer.tick = tick;
        nudge_timer.restart();
    }

    Component.onCompleted: root.sync_nudge()

    Connections {
        target: KeeptabsState
        function onFinished() {
            root.play_done(false);
            root.rephase(1);
        }
        function onWaiting_started() {
            root.play_wait(false);
            root.rephase(0);
        }
        function onWaiting_countChanged() {
            root.sync_nudge();
        }
        function onDone_countChanged() {
            root.sync_nudge();
        }
    }

    Connections {
        target: Power
        function onOn_acChanged() {
            root.sync_nudge();
        }
    }

    // Alternates wait and done nudges 5s apart, so each repeats every 10s and they never coincide.
    Timer {
        id: nudge_timer
        property int tick: 0
        interval: 5000
        repeat: true
        onTriggered: {
            nudge_timer.tick += 1;
            if (nudge_timer.tick % 2 === 0) {
                if (KeeptabsState.waiting_count > 0 && !wait_loader.active) root.play_wait(true);
            } else if (KeeptabsState.done_count > 0 && !pulse_loader.active) {
                root.play_done(true);
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Style.bar_radius(4)
        color: Style.bar_hover_bg
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    // Folds keeptabs' "glyph count" runs into {glyph, count} groups so the count can sit as a badge.
    readonly property var groups: {
        const out = [];
        for (const r of KeeptabsState.runs) {
            const text = r.text;
            const both = /^\s*(\S+)\s+(\d+)\s*$/.exec(text);
            const count_only = /^\s*(\d+)\s*$/.exec(text);
            if (both) out.push({ glyph: both[1], count: both[2], color: r.color, rise: r.rise });
            else if (count_only && out.length) out[out.length - 1].count = count_only[1];
            else if (/^\s+$/.test(text)) continue;
            else out.push({ glyph: text.trim(), count: "", color: r.color, rise: r.rise });
        }
        return out;
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Repeater {
            model: root.groups

            Item {
                id: group
                required property var modelData
                required property int index

                readonly property bool is_done: modelData.glyph === KeeptabsState.done_glyph
                readonly property bool is_wait: modelData.glyph === KeeptabsState.wait_glyph
                readonly property real content_width: glyph_text.implicitWidth + (count_text.visible ? count_text.implicitWidth * 0.6 : 0)
                implicitWidth: group.content_width
                implicitHeight: glyph_text.implicitHeight

                // Its slot reaches half the row spacing past each side, or the island's spacing at the module's ends.
                readonly property var slot: {
                    const cx = glyph_text.x + glyph_text.width / 2;
                    const cy = glyph_text.y + glyph_text.height / 2;
                    const pad_left = group.index === 0 ? root.edge_room : row.spacing / 2;
                    const pad_right = group.index === root.groups.length - 1 ? root.edge_room : row.spacing / 2;
                    return {
                        x: row.x + group.x + cx,
                        y: row.y + group.y + cy,
                        color: glyph_text.color,
                        left: cx + pad_left,
                        right: group.implicitWidth - cx + pad_right,
                        glyph_half: glyph_text.width / 2,
                        content_right: group.content_width - cx,
                        badge: count_text.visible,
                        badge_bottom: count_text.y + count_text.height - cy
                    };
                }

                Binding {
                    when: group.is_done
                    restoreMode: Binding.RestoreNone
                    target: root
                    property: "done_anchor"
                    value: group.slot
                }

                Binding {
                    when: group.is_wait
                    restoreMode: Binding.RestoreNone
                    target: root
                    property: "wait_anchor"
                    value: group.slot
                }

                Text {
                    id: glyph_text
                    // Pango rise is in 1/1024 pt; keeptabs uses +-1024 to bob the running icon.
                    y: -group.modelData.rise / 1024
                    text: group.modelData.glyph
                    color: group.modelData.color || Theme.theme_primary
                    font.family: Style.bar_font_family
                    style: Style.bar_text_style
                    styleColor: Style.bar_glow_color
                    font.pixelSize: Theme.glyph_size
                    opacity: (group.is_done && pulse_loader.active) || (group.is_wait && root.wait_hides_glyph) ? 0 : 1
                }

                Text {
                    id: count_text
                    visible: group.modelData.count !== ""
                    x: glyph_text.implicitWidth - implicitWidth * 0.4
                    y: -3
                    text: group.modelData.count
                    color: group.modelData.color || Theme.theme_primary
                    font.family: Style.bar_font_family
                    style: Style.bar_text_style
                    styleColor: Style.bar_glow_color
                    font.pixelSize: Style.bar_font_size - 3
                    font.bold: true
                }
            }
        }
    }

    Loader {
        id: pulse_loader
        property bool nudge: false
        active: false
        z: -1
        x: root.done_anchor ? root.done_anchor.x : 0
        y: root.done_anchor ? root.done_anchor.y : 0
        sourceComponent: DonePulse {
            glyph: KeeptabsState.done_glyph
            color: root.done_anchor ? root.done_anchor.color : Theme.theme_primary
            slot: root.done_anchor
            nudge: pulse_loader.nudge
            onFinished: pulse_loader.active = false
        }
    }

    Loader {
        id: wait_loader
        property bool nudge: false
        active: false
        z: item && item.under ? -1 : 0
        x: root.wait_anchor ? root.wait_anchor.x : 0
        y: root.wait_anchor ? root.wait_anchor.y : 0
        sourceComponent: WaitPulse {
            glyph: KeeptabsState.wait_glyph
            color: root.wait_anchor ? root.wait_anchor.color : Theme.theme_primary
            slot: root.wait_anchor
            nudge: wait_loader.nudge
            onFinished: wait_loader.active = false
        }
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, root.tooltip_text, "keeptabs");
            else Tooltip.hide(root);
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Popups.toggle("keeptabs", root.island, root.island_color, root.screen_name)
    }
}
