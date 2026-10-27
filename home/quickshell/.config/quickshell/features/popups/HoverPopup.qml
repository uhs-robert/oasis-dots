import QtQuick
import "HoverPolicy.js" as Policy

// Hover and click control for one module's popup: opens after `open_delay` of hover, stays while the pointer is on the
// module or the popup, closes `close_grace` after it leaves both, and a click pins it open. The decisions are in
// HoverPolicy.js; this file only owns the two timers and reads the world. Set `popup_name` and `module` (a BarModule,
// whose island anchors the popup) and call `click()` from the module's click handler.
Item {
    id: root

    property string popup_name: ""
    property var module: null
    // Off while the module is hidden or its popup should not follow hover.
    property bool enabled: true
    property int open_delay: 300
    property int close_grace: 250
    // From one module straight onto another while the first one's hover-opened popup is open: the popup is swapped in
    // place after this much hover, short enough to feel instant and long enough to skip a module the pointer only crosses.
    property int swap_delay: 60
    // The close grace while the pointer is still over the bar after leaving the module: a slow sweep across the gap to the next module (the swap target) takes longer than `close_grace`, and closing midway turns the swap into a close and a slow reopen. Leaving the bar cuts the wait back to `close_grace`.
    property int bar_grace: 900
    // How long after a close under the pointer the bar may still regain the hover it lost (HoverPolicy "settling").
    // Hyprland handed focus back within ~10 ms in the shadow; this is far above that, and the price of the margin is
    // only that a deliberate re-entry inside it needs one more move out and in.
    property int settle_ms: 600

    readonly property string mode: root._mode
    readonly property bool inside: root.enabled && !!root.module && (root.module.hovered || Popups.hover_name === root.popup_name && root.open_here)
    readonly property bool open_here: Policy.open_here(Popups.open_name, Popups.open_screen_name, root.popup_name, root.module ? root.module.screen_name : "") && (!Popups.hover_owner || Popups.hover_owner === root)
    readonly property bool over_bar: !!root.module && Popups.bar_hover_screen === root.module.screen_name
    readonly property bool nothing_open: Popups.open_name === ""
    // The open popup is another module's, opened by hover and still hover-open, on this bar: hover may swap it for this
    // one. A pinned popup has no owner; a key or IPC open leaves a stale owner whose open_here is false. A same-name
    // sibling's popup is the same window, which keeps its island once open, so it only swaps from the same island.
    readonly property var hover_owner: Popups.hover_owner
    readonly property bool other_hover_open: !!root.hover_owner && root.hover_owner !== root && root.hover_owner.mode === "hover_open" && root.hover_owner.open_here
        && !!root.module && Popups.open_screen_name === root.module.screen_name
        && (Popups.open_name !== root.popup_name || Popups.open_anchor === root.module.island)

    property string _mode: "idle"

    visible: false

    function click() {
        root.apply(Policy.clicked(root._mode, root.open_here));
    }

    function apply(r) {
        const from_mode = root._mode;
        root._mode = r.mode;
        if (r.open_timer === "start") {
            open_timer.interval = r.mode === "swapping" ? root.swap_delay : root.open_delay;
            open_timer.restart();
        }
        else if (r.open_timer === "stop") open_timer.stop();
        if (r.close_timer === "start") {
            close_timer.interval = Policy.close_delay(r.mode, root.over_bar, root.close_grace, root.bar_grace, root.settle_ms);
            close_timer.restart();
        }
        else if (r.close_timer === "stop") close_timer.stop();
        // A pinned open drops the owner only after Popups.open (below), so the popup it replaces never shows ownerless.
        if (r.mode === "pinned" && r.action !== "open") Popups.hover_owner = null;
        if (r.mode === "pinned" && root.open_here) Popups.keyboard_off = false;
        if (Policy.pin_grabs_keyboard(from_mode, r.mode, root.open_here)) Popups.grab_keyboard = true;
        // The mode is set first, so the open_name change this causes reads as ours, not as an outside open.
        if (r.action === "open" && root.module) {
            // Before the open, so a same-name sibling never sees the new popup without an owner and takes it for a pin.
            if (r.mode === "hover_open") Popups.hover_owner = root;
            Popups.open(root.popup_name, root.module.island, root.module.island_color, root.module.screen_name, "", false, false, true);
            if (r.mode !== "hover_open") Popups.hover_owner = null;
            // Taking the keyboard makes Hyprland move pointer focus to the popup, so the bar would see the pointer leave
            // the module it is still on and close the popup. A pin (click) hands the keyboard back.
            Popups.keyboard_off = r.mode === "hover_open";
        } else if (r.action === "swap" && root.module) {
            // The owner moves first, as for any hover open; the old owner then finds open_here false and goes idle on
            // its own, and must not close() or clear the owner, or a same-name sibling reads the instant as a pin.
            Popups.hover_owner = root;
            // From a same-name sibling the popup is already this one: only the owner moves.
            if (Popups.open_name !== root.popup_name) Popups.open(root.popup_name, root.module.island, root.module.island_color, root.module.screen_name, "", false, true, true);
            Popups.keyboard_off = true;
        } else if (r.action === "close" && root.open_here) Popups.close();
    }

    onInsideChanged: if (root.enabled) root.apply(Policy.inside_changed(root._mode, root.inside, root.nothing_open, root.other_hover_open))
    // Left the bar during the long grace: the pointer is going away, not to a neighbour.
    onOver_barChanged: if (!root.over_bar && root._mode === "hover_open" && close_timer.running) {
        close_timer.interval = root.close_grace;
        close_timer.restart();
    }
    onNothing_openChanged: if (root.enabled && root.nothing_open) root.apply(Policy.nothing_open_now(root._mode, root.inside))
    onOpen_hereChanged: root.apply(Policy.popup_changed(root._mode, root.open_here, root.inside))
    onEnabledChanged: if (!root.enabled) root.apply(Policy.disabled(root._mode, root.open_here))
    Component.onCompleted: if (root.open_here) root.apply(Policy.popup_changed(root._mode, true, root.inside))
    Component.onDestruction: root.apply(Policy.disabled(root._mode, root.open_here))

    Connections {
        target: Popups
        function onPopup_pressed(name) {
            if (name === root.popup_name) root.apply(Policy.popup_pressed(root._mode));
        }
    }

    Timer {
        id: open_timer
        interval: root.open_delay
        onTriggered: root.apply(Policy.open_elapsed(root._mode, root.inside, root.nothing_open, root.other_hover_open))
    }

    Timer {
        id: close_timer
        interval: root.close_grace
        onTriggered: root.apply(Policy.close_elapsed(root._mode, root.inside))
    }
}
