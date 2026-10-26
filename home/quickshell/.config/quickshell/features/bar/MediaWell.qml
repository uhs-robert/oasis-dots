import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.core
import qs.theme
import qs.features.media
import "MediaText.js" as MediaText
import "../../ui/frames/Corners.js" as Corners

// The media pocket: a recessed plate with the album art, a play/pause button, the title and artist, and a right side
// of cava or the track position. Pure view over MediaState and the settings it is handed; Media.qml owns the clicks.
Item {
    id: root

    property var player: MediaState.active
    // "cava", "position" or "hide" (the well stays, the right side goes).
    property string right_mode: "cava"
    // "inset" (pressed in, darker), "border" (island fill, thin outline) or "raised" (slightly lighter, no outline).
    property string container_style: "inset"
    readonly property var look: MediaSettings.container_look(root.container_style)
    property bool show_art: true
    property bool show_button: true
    property bool show_title: true
    property bool show_artist: true
    property string text_layout: "inline"
    property int max_chars: 24
    property bool text_scroll: false
    property int text_scroll_speed: 30
    // On a side bar: art over the play/pause button, no text and no right side, each `cell` square.
    // A compact monitor: art, button and right side, no text, close to the old 120 px cava slot.
    property bool compact: false
    property bool vertical: false
    property real cell: 24
    // False while the module is off screen, so cava and the position poll are not asked for.
    property bool active: true

    signal toggle_requested()

    // A stacked title and artist need the plate's height, so the padding around them is thinner.
    readonly property bool stacked: !root.vertical && !root.compact && root.text_lines.length > 1
    readonly property int pad: root.stacked ? 2 : 4
    readonly property real art_size: root.vertical ? root.cell : root.height - root.pad * 2
    readonly property var text_lines: MediaText.lines(root.player ? root.player.trackTitle || "" : "", root.player ? root.player.trackArtist || "" : "", root.show_title, root.show_artist, root.text_layout, root.player ? root.player.identity || "" : "")
    // A line's height over its pixel size differs per font (the GoldenEye face is much taller than most), so it is measured.
    readonly property real line_ratio: ruler.height / ruler.font.pixelSize
    FontMetrics {
        id: ruler
        font.family: root.font.family
        font.pixelSize: 20
        font.capitalization: root.font.capitalization
        font.letterSpacing: root.font.letterSpacing
    }
    // Two stacked lines must fit the well's inner height, so they shrink with it.
    function line_size(small) {
        if (root.text_lines.length < 2) return root.font.pixelSize;
        const sizes = MediaText.stacked_sizes(root.height - root.pad * 2, root.font.pixelSize, root.line_ratio);
        return small ? sizes.artist : sizes.title;
    }
    readonly property bool cava_on: root.active && !root.vertical && root.right_mode === "cava"
    readonly property real base_width: 170
    // Where the right side starts in the well's own coordinates, for the wheel: past the edge when it is not shown.
    readonly property real right_left: right.visible ? content.x + right.x : root.width + 1
    readonly property real right_width: root.right_mode === "hide" ? 0 : root.right_mode === "cava" ? 64 : 76

    implicitWidth: root.vertical ? root.cell + root.pad * 2 : Math.max(root.compact ? 0 : root.base_width, content.implicitWidth + root.side_inset * 2)
    implicitHeight: root.vertical ? root.cell * MediaSettings.vertical_cells() + (MediaSettings.vertical_cells() > 1 ? content.rowSpacing : 0) + root.pad * 2 : 24

    property font font
    font.family: Style.bar_font_family
    font.pixelSize: Style.bar_font_size
    font.capitalization: Style.bar_capitalization
    font.letterSpacing: Style.bar_letter_spacing

    // The plate takes the frame's corner profile (round, chamfer, pixel or square) through the same Corners.js the frame
    // and drawers use. Style.screen_frame_profile is the accessor a separate corner-style setting will feed; with no
    // frame the style's own rounding decides.
    readonly property var corner_profile: Style.screen_frame_profile || { corner: Style.rounded ? "round" : "square", step: 2 }
    // A round profile is the frame asking for round corners, so it rounds even where the style's own `rounded` is off; only the scale comes from the style.
    // A chamfer or pixel corner is the profile's own size.
    readonly property real corner_size: root.corner_profile.corner === "round" ? 10 * Style.corner_scale : 8
    // The 1px outline is centred on the path, so the path runs half a pixel inside the item: on the edge itself the outer half
    // is clipped and the left and right outlines come out faint or missing.
    // A chamfered or stepped corner cuts `corner_size` px off each corner, so the contents keep clear of the diagonal
    // (the art's corner would otherwise sit on it) on both ends alike.
    readonly property real side_inset: root.vertical ? root.pad : ["chamfer", "pixel"].indexOf(root.corner_profile.corner) >= 0 ? Math.max(root.pad, root.corner_size - root.pad + 2) : root.pad
    readonly property var plate_points: Corners.box_outline(root.corner_profile.corner, root.corner_size, root.corner_profile.step, root.width - 1, root.height - 1).map(p => Qt.point(p[0] + 0.5, p[1] + 0.5))

    Shape {
        id: plate
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.look.fill !== "none" || root.look.border !== "none"

        // The island's own fill shows through for "border"; "raised" lifts it with a pale wash.
        ShapePath {
            strokeWidth: -1
            fillColor: root.look.fill === "shadow" ? Qt.alpha(Style.pal.bg_shadow, 0.85) : root.look.fill === "wash" ? Qt.alpha(Style.pal.fg, 0.09) : "transparent"
            PathPolyline { path: root.plate_points }
        }

        // The faint shadow along the top edge that makes the inset read as pressed in.
        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                y1: 0
                y2: 4
                GradientStop { position: 0; color: root.look.top_shadow ? Qt.alpha(Style.pal.bg_shadow, 0.9) : "transparent" }
                GradientStop { position: 1; color: "transparent" }
            }
            PathPolyline { path: root.plate_points }
        }

        ShapePath {
            strokeWidth: root.look.border === "none" ? 0 : 1
            strokeColor: Qt.alpha(Style.pal.fg, root.look.border === "strong" ? 0.22 : 0.1)
            fillColor: "transparent"
            joinStyle: ShapePath.MiterJoin
            PathPolyline { path: root.plate_points }
        }
    }

    GridLayout {
        id: content
        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: root.vertical ? -1 : 1
        columns: root.vertical ? 1 : -1
        anchors.fill: parent
        anchors.topMargin: root.pad
        anchors.bottomMargin: root.pad
        anchors.leftMargin: root.side_inset
        anchors.rightMargin: root.side_inset
        rowSpacing: 6
        columnSpacing: 6

        AlbumArt {
            visible: root.show_art
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
            visible: root.show_button
            Layout.preferredWidth: root.art_size
            Layout.preferredHeight: root.art_size
            Layout.alignment: Qt.AlignVCenter
            radius: width / 2
            color: button_area.containsMouse ? Style.pal.bg_surface : Style.pal.bg_shadow
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
            visible: !root.vertical && !root.compact && root.text_lines.length > 0
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
            visible: !root.vertical && root.right_mode !== "hide"

            // The bars and their baseline share one box, centred in the plate however tall the plate is.
            Item {
                id: cava_box
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Math.min(parent.height - 4, 16)

                Rectangle {
                    visible: root.right_mode === "cava"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Qt.alpha(Theme.theme_primary, 0.3)
                }

                CavaViewer { active: root.cava_on && MediaState.playing && PowerSource.on_ac }

                CavaBars {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.height
                    active: root.cava_on && MediaState.playing && PowerSource.on_ac
                }
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
