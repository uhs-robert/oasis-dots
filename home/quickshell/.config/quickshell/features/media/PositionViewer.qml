import QtQuick

// Keeps MediaState polling the track position while `active`; the position twin of CavaViewer.
QtObject {
    id: root

    property bool active: false

    onActiveChanged: if (root.active) MediaState.register_position(root); else MediaState.unregister_position(root)
    Component.onCompleted: if (root.active) MediaState.register_position(root)
    Component.onDestruction: MediaState.unregister_position(root)
}
