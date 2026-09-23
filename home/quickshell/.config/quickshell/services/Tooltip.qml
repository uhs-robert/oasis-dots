// home/quickshell/.config/quickshell/services/Tooltip.qml
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    property var anchor_item: null
    property string text: ""
    property bool visible: false

    property var pending_item: null
    property string pending_text: ""

    function show(item, t) {
        if (root.pending_item === item && root.pending_text === t) return;
        root.pending_item = item;
        root.pending_text = t;
        delay_timer.restart();
    }

    function hide() {
        delay_timer.stop();
        root.visible = false;
        root.anchor_item = null;
        root.pending_item = null;
    }

    Connections {
        target: Popups
        function onOpen_nameChanged() {
            if (Popups.open_name !== "") root.hide();
        }
    }

    Timer {
        id: delay_timer
        interval: 400
        onTriggered: {
            root.anchor_item = root.pending_item;
            root.text = root.pending_text;
            root.visible = root.pending_item !== null;
        }
    }
}
