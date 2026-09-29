// home/quickshell/.config/quickshell/components/LazyPopup.qml
import QtQuick
import Quickshell
import "../services"

// Builds its popup on open and drops it once the close animation has hidden it.
LazyLoader {
    id: root

    required property string name

    // Latched from the popup's visibility; reading item.visible in the binding loops through active.
    property bool showing: false

    active: Popups.load_name === root.name || root.showing

    // A named property, since LazyLoader's default property is the popup itself.
    property Connections watch: Connections {
        target: root.item
        ignoreUnknownSignals: true
        function onVisibleChanged() {
            root.showing = !!root.item && root.item.visible;
        }
    }
}
