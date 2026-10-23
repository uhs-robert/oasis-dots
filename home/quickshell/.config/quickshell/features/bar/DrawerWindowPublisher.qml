import QtQuick

// Keeps one drawer's window rect in ScreenFrames.drawer_windows under its own key while it has one, so the entry is
// cleared when the rect goes null, the screen changes or the drawer is destroyed, and never touches another drawer's.
QtObject {
    id: root

    property string screen_name: ""
    // Null while the drawer is not translucent or not visible.
    property var rect: null

    readonly property string key: String(root)
    property string published_screen_name: ""

    function publish() {
        const name = root.rect ? root.screen_name : "";
        if (root.published_screen_name !== "" && root.published_screen_name !== name) ScreenFrames.set_drawer_window(root.published_screen_name, root.key, null);
        root.published_screen_name = name;
        if (name !== "") ScreenFrames.set_drawer_window(name, root.key, root.rect);
    }
    onRectChanged: root.publish()
    onScreen_nameChanged: root.publish()
    Component.onDestruction: if (root.published_screen_name !== "") ScreenFrames.set_drawer_window(root.published_screen_name, root.key, null)
}
