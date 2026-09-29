// home/quickshell/.config/quickshell/components/LazyPopup.qml
import QtQuick
import Quickshell
import "../services"

// Builds its popup on open and drops it once the close animation has hidden it.
LazyLoader {
    id: root

    required property string name

    active: Popups.load_name === root.name || (root.item !== null && root.item.visible)
}
