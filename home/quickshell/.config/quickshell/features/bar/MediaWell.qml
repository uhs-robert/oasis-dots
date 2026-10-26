import QtQuick
import QtQuick.Layouts
import qs.core
import qs.theme
import qs.features.media
import "MediaText.js" as MediaText

// The media pocket: a recessed plate with the album art, a play/pause button, the title and artist, and a right side
// of cava or the track position. Pure view over MediaState and the settings it is handed; Media.qml owns the clicks.
Item {
    id: root

    property var player: MediaState.active
    // "cava", "position" or "hide" (the well stays, the right side goes).
    property string right_mode: "cava"
    property bool show_title: true
    property bool show_artist: true
    property string text_layout: "inline"
    property int max_chars: 24
    property bool text_scroll: false
    property int text_scroll_speed: 30
    // False while the module is off screen, so cava and the position poll are not asked for.
    property bool active: true

    signal toggle_requested()

    readonly property int pad: 4
    readonly property real art_size: root.height - root.pad * 2
    readonly property var text_lines: MediaText.lines(root.player ? root.player.trackTitle || "" : "", root.player ? root.player.trackArtist || "" : "", root.show_title, root.show_artist, root.text_layout)
    // Two stacked lines must fit the well's inner height, so they shrink with it.
    function line_size(small) {
        const inner = root.height - root.pad * 2;
        const stacked = root.text_lines.length > 1;
        if (small) return Math.max(7, Math.min(root.font.pixelSize - 3, Math.floor(inner * 0.36)));
        return stacked ? Math.max(8, Math.min(root.font.pixelSize, Math.floor(inner * 0.5))) : root.font.pixelSize;
    }
    readonly property bool cava_on: root.active && root.right_mode === "cava"
    readonly property real base_width: 170
    readonly property real right_width: root.right_mode === "hide" ? 0 : root.right_mode === "cava" ? 64 : 76

    implicitWidth: Math.max(root.base_width, content.implicitWidth + root.pad * 2)
    implicitHeight: 24

    property font font
    font.family: Style.bar_font_family
    font.pixelSize: Style.bar_font_size
    font.capitalization: Style.bar_capitalization
    font.letterSpacing: Style.bar_letter_spacing

    // Darker than the island plate whatever its fill, with a faint shadow along the top edge.
    Rectangle {
        id: plate
        anchors.fill: parent
        radius: Style.radius(8)
        // Black rather than a palette tint: a recess has to read darker on every bar color, and the strip styles' own
        // shadow token is close to the bar itself.
        color: Qt.rgba(0, 0, 0, 0.38)
        border.width: 1
        border.color: Qt.alpha(Style.pal.fg, 0.1)
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 4
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.35) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: 6

        AlbumArt {
            Layout.preferredWidth: root.art_size
            Layout.preferredHeight: root.art_size
            Layout.alignment: Qt.AlignVCenter
            source: root.player ? root.player.trackArtUrl : ""
            has_art: !!root.player && root.player.trackArtUrl !== ""
            corner: 5
            glyph_size: Math.round(root.art_size * 0.55)
            shadowed: false
        }

        Rectangle {
            id: button
            Layout.preferredWidth: root.art_size
            Layout.preferredHeight: root.art_size
            Layout.alignment: Qt.AlignVCenter
            radius: width / 2
            color: button_area.containsMouse ? Style.pal.bg_surface : Qt.rgba(0, 0, 0, 0.45)
            border.width: 1
            border.color: Qt.alpha(Style.pal.fg, 0.18)
            opacity: root.player && root.player.canTogglePlaying ? 1 : 0.4

            Text {
                anchors.centerIn: parent
                text: MediaState.playing ? "\u{f04c}" : "\u{f04b}"
                color: Style.pal.fg
                font.family: Style.font_family
                font.pixelSize: Math.round(root.art_size * 0.6)
            }

            MouseArea {
                id: button_area
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.toggle_requested()
            }
        }

        Column {
            Layout.alignment: Qt.AlignVCenter
            visible: root.text_lines.length > 0
            spacing: 0

            Repeater {
                model: root.text_lines

                MarqueeText {
                    required property var modelData
                    full_text: modelData.text
                    max_chars: root.max_chars
                    scroll: root.text_scroll && root.active
                    speed: root.text_scroll_speed
                    color: modelData.small ? Qt.alpha(Style.bar_fg, 0.7) : Style.bar_fg
                    font.family: root.font.family
                    font.pixelSize: root.line_size(modelData.small)
                    font.capitalization: root.font.capitalization
                    font.letterSpacing: root.font.letterSpacing
                    style: Style.bar_text_style
                    style_color: Style.bar_glow_color
                }
            }
        }

        Item {
            id: right
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: root.right_width
            visible: root.right_mode !== "hide"

            Rectangle {
                visible: root.right_mode === "cava"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                height: 1
                color: Qt.alpha(Theme.theme_primary, 0.3)
            }

            CavaViewer { active: root.cava_on && MediaState.playing && PowerSource.on_ac }

            CavaBars {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                height: Math.min(parent.height - 4, 16)
                active: root.cava_on && MediaState.playing && PowerSource.on_ac
            }

            PositionLine {
                visible: root.right_mode === "position"
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                font.family: root.font.family
                font.pixelSize: Math.max(8, root.font.pixelSize - 2)
                color: Style.bar_fg
            }
        }
    }
}
