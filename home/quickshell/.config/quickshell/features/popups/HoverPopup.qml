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

    readonly property string mode: root._mode
    readonly property bool inside: root.enabled && !!root.module && (root.module.hovered || Popups.hover_name === root.popup_name && Popups.open_name === root.popup_name)
    readonly property bool open_here: Popups.open_name === root.popup_name
    readonly property bool nothing_open: Popups.open_name === ""

    property string _mode: "idle"

    visible: false

    function click() {
        root.apply(Policy.clicked(root._mode, root.open_here));
    }

    function apply(r) {
        root._mode = r.mode;
        if (r.open_timer === "start") open_timer.restart();
        else if (r.open_timer === "stop") open_timer.stop();
        if (r.close_timer === "start") close_timer.restart();
        else if (r.close_timer === "stop") close_timer.stop();
        if (r.mode === "pinned" && root.open_here) Popups.keyboard_off = false;
        // The mode is set first, so the open_name change this causes reads as ours, not as an outside open.
        if (r.action === "open" && root.module) {
            Popups.open(root.popup_name, root.module.island, root.module.island_color, root.module.screen_name);
            // Taking the keyboard makes Hyprland move pointer focus to the popup, so the bar would see the pointer leave
            // the module it is still on and close the popup. A pin (click) hands the keyboard back.
            Popups.keyboard_off = r.mode === "hover_open";
        } else if (r.action === "close" && root.open_here) Popups.close();
    }

    onInsideChanged: if (root.enabled) root.apply(Policy.inside_changed(root._mode, root.inside, root.nothing_open))
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
        onTriggered: root.apply(Policy.open_elapsed(root._mode, root.inside, root.nothing_open))
    }

    Timer {
        id: close_timer
        interval: root.close_grace
        onTriggered: root.apply(Policy.close_elapsed(root._mode, root.inside))
    }
}
