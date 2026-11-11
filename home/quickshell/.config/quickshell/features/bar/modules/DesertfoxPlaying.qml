import QtQuick
import qs.theme
import qs.features.bar
import qs.features.desertfox
import qs.features.popups

// The Firefox tab making sound, from DesertFox's event stream. It sits beside `media` and does not replace it: media
// speaks MPRIS and knows nothing of tabs, so only this chip can raise the tab's window. Click jumps to the tab, right or
// middle click pauses it. Hidden while no tab plays or DesertFox is not sharing its tabs.
BarModule {
    id: root
    module_name: "desertfox_playing"
    has_popup: false
    wash: false

    readonly property var tab: NowPlayingState.tab

    // A side bar's column is too narrow for a title.
    shown: root.counted && root.tab !== null
    tooltip_title: "Playing in Firefox"
    tooltip_text: root.tab ? root.tab.title + "\nClick: go to the tab. Right click: pause." : ""
    onTooltip_textChanged: if (root.hovered) Tooltip.show(root, root.tooltip_text, root.tooltip_title)
    implicitWidth: root.shown ? chip.width : 0
    implicitHeight: chip.height

    // Only a bar that can show the chip holds the stream and its retries; a side bar's module never draws.
    readonly property bool counted: !root.vertical
    property bool registered: false
    onCountedChanged: root.sync_count()
    Component.onCompleted: root.sync_count()
    Component.onDestruction: if (root.registered) NowPlayingState.mounted_modules--

    function sync_count(): void {
        if (root.counted === root.registered) return;
        root.registered = root.counted;
        NowPlayingState.mounted_modules += root.counted ? 1 : -1;
    }

    Rectangle {
        id: chip
        anchors.verticalCenter: parent.verticalCenter
        width: label.implicitWidth + 12
        height: label.implicitHeight + 4
        radius: Style.bar_radius(4)
        color: Qt.alpha(Theme.theme_secondary, 0.2)
        border.width: 1
        border.color: Qt.alpha(Theme.theme_secondary, 0.6)

        Text {
            id: label
            anchors.centerIn: parent
            text: "♪ " + NowPlayingState.label
            textFormat: Text.PlainText
            color: Theme.theme_secondary
            font.family: Style.font_family
            font.pixelSize: Style.bar_font_size
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) NowPlayingState.jump();
            else NowPlayingState.pause();
        }
    }
}
