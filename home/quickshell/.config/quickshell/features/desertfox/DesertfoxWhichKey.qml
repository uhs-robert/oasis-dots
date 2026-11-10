import QtQuick
import Quickshell
import qs.features.popups

// DesertFox's which-key on the overlay layer, drawn by its own WhichKey window beside the HyprVim one. It follows the
// state file: it opens when the file holds a panel and Firefox has focus, folds back when either stops being true, and
// opens again on refocus only if the file still holds the panel. A mode change rewrites the file but keeps the
// panel's seq, so it does not reopen the drawer.
Scope {
    id: root

    // The panel last handed to the window, by its key; "" when none is.
    property string shown_key: ""

    function sync(): void {
        if (!DesertfoxState.has_panel) {
            root.shown_key = "";
            if (whichkey.wanted) whichkey.hide_now();
            return;
        }
        if (root.shown_key === DesertfoxState.panel_key && whichkey.wanted) return;
        root.shown_key = DesertfoxState.panel_key;
        whichkey.show_object(DesertfoxState.panel_payload);
    }

    Connections {
        target: DesertfoxState
        function onHas_panelChanged() { root.sync(); }
        function onPanel_keyChanged() { root.sync(); }
    }

    Component.onCompleted: root.sync()

    WhichKey {
        id: whichkey
    }
}
