pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.theme
import qs.features.bar
import "HoverPolicy.js" as Policy

Singleton {
    id: root

    property string open_name: ""
    // The open popup once it has finished drawing in; empty while it animates, and while nothing is open.
    property string settled_name: ""
    // A popup still animating out after close(); its layer is mapped until this clears.
    property string closing_name: ""
    // Set just before open_name, so a LazyPopup builds its popup closed and sees the open as a change.
    property string load_name: ""
    property var open_anchor: null
    property color open_color: Theme.bg_mantle
    property string open_screen_name: ""
    // While set, the open popup and the scrim take no keyboard focus and no pointer input, so IPC can show one on a screen the owner is not using.
    // Cleared by every open() that does not ask for it, and by close().
    property bool hands_off: false
    // Whether the open popup holds the keyboard: Popup.qml gives a hands-off popup none. A passive popup is never the open one.
    readonly property bool takes_keyboard: open_name !== "" && open_screen_name !== "" && !hands_off
    // Asks the open popup for the keyboard; it holds it Exclusive until the window is active, then lets go.
    // The popup clears it straight away when its window already has the keyboard.
    property bool grab_keyboard: false
    // Popup name to reopen on Backspace, e.g. "start" for popups opened from the Start menu.
    property string back_name: ""
    // The popup the pointer is over right now (Popup.qml reports it), so a module's hover helper can tell the pointer moving onto its popup from leaving.
    property string hover_name: ""
    // The HoverPopup that hover-opened the open popup; null when nothing did or once it is pinned. Two modules can share a popup name (system:cpu and system:memory), so only this one reads the open as its own.
    // A sibling reads an open popup with no owner as an outside open and pins, so close() clears it only after open_name has moved, and a HoverPopup's pinned open only after Popups.open(). Every other open (key, IPC, walk, back) clears it too, or the stale owner would make the module of a key-opened popup read it as not its own.
    property var hover_owner: null
    // A hover swap in flight (HoverPopup, `swap`): { name, to, screen_name, extent }, set by open() before open_name
    // moves and cleared once the outgoing window `name` hides. The outgoing popup fades instead of folding up and the
    // incoming one `to` grows from the outgoing one's drawn `extent` instead of dropping, so the panel stays out.
    property var swap_from: null
    // Asks the outgoing popup for its drawn extent, which only its window knows; it answers through report_swap_extent.
    signal measure_swap(string name)
    function report_swap_extent(name, extent) {
        if (root.swap_from && root.swap_from.name === name) root.swap_from = Object.assign({}, root.swap_from, { extent: extent });
    }
    function swap_done(name) {
        if (root.swap_from && root.swap_from.name === name) root.swap_from = null;
    }
    // A hidden window sends no leave, so each open starts from "not over it".
    onOpen_nameChanged: {
        root.hover_name = "";
        root.keyboard_off = false;
    }
    // A press inside the open popup: a hover-opened popup is then pinned (HoverPopup listens).
    signal popup_pressed(string name)
    function set_popup_hover(name, hovered) {
        if (hovered) root.hover_name = name;
        else if (root.hover_name === name) root.hover_name = "";
    }

    // The screen whose bar the pointer is over, anywhere on it (Bar reports it), so a hover helper can tell the pointer crossing the gap to the next module from leaving the bar.
    property string bar_hover_screen: ""
    function set_bar_hover(screen_name, hovered) {
        if (hovered) root.bar_hover_screen = screen_name;
        else if (root.bar_hover_screen === screen_name) root.bar_hover_screen = "";
    }

    // A hover-opened popup takes no keyboard until it is pinned (see HoverPopup); every other open takes it as before.
    property bool keyboard_off: false

    // The Power action the "power" popup asks to confirm.
    property string power_action: ""

    // screen_name -> { module_name: { item, color } }, so each bar keeps its own anchors.
    property var default_anchors: ({})

    // screen_name -> ordered popup names in bar order, kept by Bar for Ctrl+H/L walking.
    property var popup_order: ({})

    // Lets a module register the item/color its popup anchors to when opened without a click (IPC).
    // `owner` is the registering module; it defaults to the anchor item (the clock has no module).
    function register_default(name, item, color, screen_name, owner, back_to) {
        if (!default_anchors[screen_name]) default_anchors[screen_name] = {};
        default_anchors[screen_name][name] = { item: item, color: color, owner: owner || item, back_to: back_to || "" };
    }

    function register_order(screen_name, names) {
        popup_order[screen_name] = names;
    }

    // Called when a bar is destroyed so a popup never anchors to a deleted item.
    function unregister_screen(screen_name) {
        if (open_screen_name === screen_name) close();
        delete default_anchors[screen_name];
        delete popup_order[screen_name];
    }

    // Removes an entry only if its owner registered it: a rebuilt module shares the island
    // item with the one being destroyed, so matching on the item would drop the new entry.
    function unregister(name, screen_name, owner) {
        const entry = default_anchors[screen_name] && default_anchors[screen_name][name];
        if (!entry || entry.owner !== owner) return;
        delete default_anchors[screen_name][name];
        if (open_screen_name === screen_name && open_name === name) close();
    }

    // Quickshell nulls a JS reference to a QObject once it's destroyed, so a plain truthy check finds stale entries.
    function find_in_screen(screen_name, name) {
        const entry = default_anchors[screen_name] && default_anchors[screen_name][name];
        return entry && entry.item ? Object.assign({ screen_name: screen_name }, entry) : null;
    }

    // Prefers the focused monitor's bar, falling back to any bar that has this module.
    function find_default(name) {
        const focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        if (focused) {
            const found = root.find_in_screen(focused, name);
            if (found) return found;
            const screen = Quickshell.screens.find(s => s.name === focused);
            const rule = screen ? BarSettings.rule_for(screen) : null;
            if (screen && (!rule || rule.bar === false)) return null;
        }
        for (const screen_name in default_anchors) {
            const found = root.find_in_screen(screen_name, name);
            if (found) return found;
        }
        return null;
    }

    // Anchors are island bodies; read the Island's color, since a shaded body is transparent.
    function anchor_color(found) {
        const island = found.item ? found.item.parent : null;
        return island && island.bg_color !== undefined ? island.bg_color : found.color;
    }

    // Whether the open popup is one the bar order reaches, so a walk key has somewhere to go. The picker is not, even when
    // it was opened from a bar popup (back_name), because Ctrl+J/K are its own row keys.
    function walkable() {
        if (root.open_name === "picker") return false;
        const order = root.popup_order[root.open_screen_name] || [];
        return order.indexOf(root.open_name) !== -1 || (root.back_name !== "" && order.indexOf(root.back_name) !== -1);
    }

    // Steps to the next (delta 1) or previous (delta -1) module's popup in that screen's bar order, wrapping.
    function walk(delta) {
        const screen_name = root.open_screen_name;
        const order = root.popup_order[screen_name] || [];
        if (order.length === 0) return;
        let idx = order.indexOf(root.open_name);
        if (idx === -1) {
            if (root.back_name === "") return;
            idx = order.indexOf(root.back_name);
            if (idx === -1) return;
        }
        const n = order.length;
        for (let step = 1; step <= n; step++) {
            const candidate = order[((idx + delta * step) % n + n) % n];
            const found = root.find_in_screen(screen_name, candidate);
            if (found) {
                root.open(candidate, found.item, root.anchor_color(found), screen_name, found.back_to);
                return;
            }
        }
    }

    // `swap`: a hover swap from the open popup (see swap_from, HoverPolicy.swap_source).
    // `keep_owner`: the caller is the HoverPopup that has just set hover_owner; any other open drops the owner.
    function open(name, anchor_item, color, screen_name, back_to, hands_off, swap, keep_owner) {
        let back = back_to || "";
        // A same-popup open emits no open_name change, so its hover owner has to be told (see keep_owner below).
        const reopened_owner = name === open_name ? root.hover_owner : null;
        root.swap_from = Policy.swap_source(!!swap && !!anchor_item, open_name, open_screen_name, name, screen_name || "");
        if (root.swap_from) root.measure_swap(root.swap_from.name);
        if (anchor_item) {
            open_anchor = anchor_item;
            open_color = color || Theme.bg_mantle;
            open_screen_name = screen_name || "";
        } else {
            const found = root.find_default(name);
            open_anchor = found ? found.item : null;
            open_color = found ? root.anchor_color(found) : (color || Theme.bg_mantle);
            // A popup with no module (the docked picker) opens on the screen it names.
            open_screen_name = found ? found.screen_name : (screen_name || (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""));
            if (found && !back) back = found.back_to || "";
        }
        load_name = name;
        open_name = name;
        if (!keep_owner) {
            if (reopened_owner) reopened_owner.pin();
            root.hover_owner = null;
        }
        back_name = back;
        grab_keyboard = false;
        // After open_name moves, so a hands-off popup being replaced keeps its latched flag through its close animation.
        root.hands_off = !!hands_off;
    }

    // Opens for a keybind or IPC call, where the pointer is not on the popup: asks for the keyboard up front, since a
    // popup replacing a keyboard-holding one (Settings) is otherwise never focused and its Ctrl+H/L Shortcuts stay dead.
    // Hover and click opens go through open() and keep the plain OnDemand focus.
    function open_with_keyboard(name) {
        root.open(name, undefined);
        grab_keyboard = true;
    }

    // Opens on the named screen, never the focused one: anchored to that bar's module when it has one, else unanchored.
    // False when no such screen exists.
    function open_on(name, screen_name, hands_off) {
        if (!Quickshell.screens.some(s => s.name === screen_name)) return false;
        // An open popup only latches its screen as it opens, so moving it to another screen means closing and reopening.
        if (root.open_name === name && root.open_screen_name !== screen_name) {
            root.close();
            Qt.callLater(() => root.open_on(name, screen_name, hands_off));
            return true;
        }
        const found = root.find_in_screen(screen_name, name);
        if (found) {
            root.open(name, found.item, root.anchor_color(found), screen_name, found.back_to, hands_off);
            return true;
        }
        open_anchor = null;
        open_color = Theme.bg_mantle;
        open_screen_name = screen_name;
        root.swap_from = null;
        load_name = name;
        open_name = name;
        root.hover_owner = null;
        back_name = "";
        grab_keyboard = false;
        root.hands_off = !!hands_off;
        return true;
    }

    // Takes the keyboard back for the open popup on the focused monitor when it has lost it; false when there is nothing to do.
    function focus_open() {
        const focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        if (settled_name === "" || settled_name !== open_name || hands_off) return false;
        if (open_screen_name !== focused) return false;
        grab_keyboard = true;
        return grab_keyboard;
    }

    function mark_settled(name, settled) {
        if (settled) settled_name = name;
        else if (settled_name === name) settled_name = "";
    }

    function mark_closing(name, closing) {
        if (closing) closing_name = name;
        else if (closing_name === name) closing_name = "";
    }

    function close() {
        load_name = "";
        open_name = "";
        open_anchor = null;
        open_screen_name = "";
        back_name = "";
        // After open_name clears; see hover_owner.
        hover_owner = null;
        // After open_name clears, so the closing popup keeps ignoring input through its close animation.
        hands_off = false;
        grab_keyboard = false;
        // A popup closing mid-swap folds up as usual; the outgoing one already fading finishes on its own.
        swap_from = null;
    }

    // Closes the popup, then runs `fn` once Hyprland has unmapped its layer. Anything that opens a window from a popup
    // goes through here: a window that maps while the popup holds the keyboard is left unfocused, and the layer
    // closing then hands focus back to the window that had it before.
    function after_close(fn) {
        // A non-empty queue means the layer is still closing, so a second call waits too.
        if (root.open_name === "" && root.after_close_queue.length === 0) return fn();
        root.after_close_queue = root.after_close_queue.concat([fn]);
        root.close();
        after_close_fallback.restart();
    }

    function run_after_close_queue() {
        after_close_fallback.stop();
        const queue = root.after_close_queue;
        root.after_close_queue = [];
        for (const fn of queue) fn();
    }

    // Reopens the popup that opened the current one, keeping the same anchor/color/screen.
    function back() {
        if (root.back_name === "") return;
        const found = root.find_in_screen(root.open_screen_name, root.back_name);
        root.open(root.back_name, root.open_anchor, root.open_color, root.open_screen_name, found ? found.back_to : "");
    }

    function toggle(name, anchor_item, color, screen_name) {
        if (open_name === name) close();
        else open(name, anchor_item, color, screen_name);
    }

    property var after_close_queue: []

    Connections {
        target: Hyprland
        enabled: root.after_close_queue.length > 0
        function onRawEvent(event) {
            if (event.name === "closelayer" && event.data === "quickshell-popup") root.run_after_close_queue();
        }
    }

    // In case the closelayer event never arrives, the action still runs, just without the focus guarantee.
    Timer {
        id: after_close_fallback
        interval: 1000
        onTriggered: root.run_after_close_queue()
    }

    // Keybind workspace switches never touch the scrim, so close here too.
    Connections {
        target: Hyprland
        enabled: root.open_name !== ""
        function onRawEvent(event) {
            if (event.name === "workspacev2") root.close();
        }
    }
}
