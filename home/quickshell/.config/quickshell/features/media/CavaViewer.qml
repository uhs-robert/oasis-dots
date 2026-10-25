import QtQuick

// Keeps cava running while `active`: registers itself on CavaState and unregisters when inactive or destroyed.
QtObject {
    id: root

    property bool active: false

    onActiveChanged: if (root.active) CavaState.register(root); else CavaState.unregister(root)
    Component.onCompleted: if (root.active) CavaState.register(root)
    Component.onDestruction: CavaState.unregister(root)
}
