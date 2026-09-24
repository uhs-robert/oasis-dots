// home/quickshell/.config/quickshell/services/Tooltip.qml
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    property var anchor_item: null
    property string title: ""
    property string text: ""
    property bool visible: false
    // The island body the shelf drops from; its color and screen are latched with it.
    property var island: null
    property color island_color: "transparent"
    property string screen_name: ""

    property var pending_item: null
    property string pending_text: ""
    property string pending_title: ""

    // While the shelf is up, hovering another module swaps it at once instead of waiting out the delay.
    function show(item, t, name) {
        if (!item || Popups.open_name !== "") return;
        hide_timer.stop();
        root.pending_item = item;
        root.pending_text = t || "";
        root.pending_title = (name || "").toUpperCase();
        if (root.visible) root.commit();
        else delay_timer.restart();
    }

    // A leave from an item that is no longer the hovered one is stale: the enter on the next one already ran.
    function hide(item) {
        if (item && item !== root.pending_item) return;
        delay_timer.stop();
        if (root.visible) hide_timer.restart();
        else root.pending_item = null;
    }

    function clear() {
        delay_timer.stop();
        hide_timer.stop();
        root.visible = false;
        root.anchor_item = null;
        root.pending_item = null;
    }

    function island_of(item) {
        for (let p = item; p; p = p.parent) {
            if (p.parent && p.parent.body_item === p) return p;
        }
        return null;
    }

    function screen_of(item) {
        for (let p = item; p; p = p.parent) {
            if (typeof p.screen_name === "string" && p.screen_name !== "") return p.screen_name;
        }
        return "";
    }

    function commit() {
        const item = root.pending_item;
        const body = root.island_of(item);
        if (!body || Popups.open_name !== "") {
            root.clear();
            return;
        }
        root.anchor_item = item;
        root.island_color = body.parent.bg_color;
        root.screen_name = root.screen_of(item);
        root.island = body;
        root.title = root.pending_title;
        root.text = root.pending_text;
        root.visible = true;
    }

    Connections {
        target: Popups
        function onOpen_nameChanged() {
            if (Popups.open_name !== "") root.clear();
        }
    }

    Timer {
        id: delay_timer
        interval: 400
        onTriggered: root.commit()
    }

    Timer {
        id: hide_timer
        interval: 200
        onTriggered: root.clear()
    }
}
