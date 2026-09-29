// home/quickshell/.config/quickshell/settings/SkinThumb.qml
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"
import "../lock"

// A lock or login skin drawn at screen size and scaled down, with fake auth state.
Rectangle {
    id: root

    property var popup: null
    property string skin: "simple"
    property string tint: "primary"
    property bool login: false
    property bool music: true
    // The skin loads only while true.
    property bool active: true
    readonly property bool has_music: !!skin_loader.item && skin_loader.item.has_music === true
    readonly property real screen_w: root.popup && root.popup.screen ? root.popup.screen.width : 1920
    readonly property real screen_h: root.popup && root.popup.screen ? root.popup.screen.height : 1080

    Layout.fillWidth: true
    Layout.preferredHeight: Math.round(width * screen_h / screen_w)
    color: Theme.bg_shadow
    border.width: 1
    border.color: root.popup ? root.popup.st.frame_border_color : Style.frame_border_color
    radius: Style.px(4)
    clip: true

    function load() {
        if (!root.active) {
            skin_loader.source = "";
            return;
        }
        skin_loader.setSource(LockSkins.url_for(root.skin), { ctx: fake });
        if (skin_loader.status === Loader.Error) skin_loader.setSource(Qt.resolvedUrl("../lock/LockScreen.qml"), { ctx: fake });
    }

    onSkinChanged: root.load()
    onActiveChanged: root.load()
    Component.onCompleted: root.load()

    LockCtx {
        id: fake
        typing: true
        tint: root.tint
        login: root.login
        music: root.music
    }

    Loader {
        id: skin_loader
        width: root.screen_w
        height: root.screen_h
        scale: (root.width - 2) / root.screen_w
        transformOrigin: Item.TopLeft
        x: 1
        y: 1
    }
}
