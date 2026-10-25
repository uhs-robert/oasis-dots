import QtQuick
import qs.core
import qs.theme
import qs.features.media
import qs.features.popups
import qs.features.bar

// Audio bars in this module's own slot on the strip styles (full bar, floating strip, frame). Island styles draw
// cava in the clock island and use this entry only as their on/off switch; side bars and lualine draw none here.
BarModule {
    id: root
    module_name: "cava"
    has_popup: false
    wash: false

    shown: Style.strip_shape && !root.vertical && MediaState.playing && PowerSource.on_ac
    implicitWidth: shown ? 120 : 0
    implicitHeight: root.bar_height

    CavaViewer { active: root.shown }

    CavaBars {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Math.min(root.bar_height - 12, 18)
        active: root.shown
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Popups.toggle("media", root.island, root.island_color, root.screen_name)
    }
}
