// home/quickshell/.config/quickshell/bar/modules/Media.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components"

Item {
    id: root

    property bool compact: false
    property string screen_name: ""
    property Item island: null
    property color island_color: Theme.bg_core

    WheelStepper {
        id: wheel_stepper
    }

    readonly property var player: MediaState.active
    readonly property bool shown: !!root.player
    visible: shown
    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    readonly property string label_text: {
        if (!root.player) return "";
        const title = root.player.trackTitle || "";
        const artist = root.player.trackArtist || "";
        return artist ? artist + " — " + title : title;
    }

    readonly property string tooltip_text: {
        if (!root.player) return "";
        const lines = [root.player.trackTitle || "Unknown title"];
        if (root.player.trackArtist) lines.push(root.player.trackArtist);
        if (root.player.trackAlbum) lines.push(root.player.trackAlbum);
        lines.push(root.player.identity || "");
        return lines.join("\n");
    }

    onIslandChanged: if (root.island) Popups.register_default("media", root.island, root.island_color, root.screen_name, root)
    Component.onDestruction: Popups.unregister("media", root.screen_name, root)

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Style.bar_radius(4)
        color: Style.bar_hover_bg
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    RowLayout {
        id: row
        spacing: 6

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: "\u{f001}"
            color: Theme.theme_primary
            opacity: root.player && root.player.isPlaying ? 1 : 0.5
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Theme.glyph_size
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: 240
            elide: Text.ElideRight
            visible: !root.compact
            text: root.label_text
            color: Style.bar_fg
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_font_size
            font.capitalization: Style.bar_capitalization
            font.letterSpacing: Style.bar_letter_spacing
        }
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, root.tooltip_text);
            else Tooltip.hide();
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                MediaState.toggle();
            } else {
                Popups.toggle("media", root.island, root.island_color, root.screen_name);
            }
        }
        onWheel: wheel => {
            const notches = wheel_stepper.consume(wheel.angleDelta.y || wheel.pixelDelta.y);
            if (notches === 0) return;
            if (notches > 0) MediaState.next();
            else MediaState.previous();
        }
    }
}
