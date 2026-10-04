// home/quickshell/.config/quickshell/components/picker/Loupe.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../services"
import "loupe" as LoupeSkins

// The region selector's magnifier: a zoomed, skinned view of `source` around `at`, placed beside the cursor.
Item {
    id: root

    required property point at
    required property Item source
    required property real sample_scale
    required property bool pixel_mode
    required property string screen_name
    required property real screen_x
    required property real screen_y
    required property real area_width
    required property real area_height
    required property bool has_sel
    required property rect sel
    required property string pixel_image
    required property size frame_size
    required property bool scan_complete
    required property int scan_step
    required property int scan_steps
    readonly property real lens: Screenshot.lens_size
    readonly property real pad: 6
    readonly property int zoom: Screenshot.zoom
    // Odd, so one buffer pixel sits in the center.
    readonly property int count: Math.floor(root.lens / root.zoom) % 2 === 0 ? Math.floor(root.lens / root.zoom) + 1 : Math.floor(root.lens / root.zoom)
    readonly property int half: (root.count - 1) / 2
    readonly property real sample_half: (root.half + 1) / root.sample_scale
    readonly property real view: root.count * root.zoom
    readonly property int bx: Math.floor(root.at.x * root.sample_scale)
    readonly property int by: Math.floor(root.at.y * root.sample_scale)
    readonly property bool skinned: skin_loader.status === Loader.Ready
    readonly property var skin: root.skinned ? skin_loader.item : null
    readonly property bool own_readout: root.skinned && root.skin.own_readout
    readonly property var rgb: root.parse_rgb(Screenshot.pixel_hex)
    // Zoom mode raises it so the loupe never sits inside the area it magnifies.
    property real min_gap: 0
    readonly property real gap: Math.max(root.min_gap, root.skinned ? root.skin.gap : 28)
    readonly property real flip_gap: root.skinned ? root.skin.flip_gap : root.gap

    function parse_rgb(hex) {
        if (hex.length < 7) return [0, 0, 0];
        return [parseInt(hex.substr(1, 2), 16), parseInt(hex.substr(3, 2), 16), parseInt(hex.substr(5, 2), 16)];
    }
    function pad4(v) {
        const n = Math.round(v);
        return (n < 0 ? "-" : "") + String(Math.abs(n)).padStart(4, "0");
    }

    width: root.skinned ? root.skin.implicitWidth : root.view + root.pad * 2
    height: root.skinned ? root.skin.implicitHeight : root.view + root.pad * 2 + coords.implicitHeight + 4 + (root.pixel_mode ? swatch_row.height + 4 : 0)
    x: root.at.x + root.gap + root.width <= root.area_width ? root.at.x + root.gap : root.at.x - root.flip_gap - root.width
    y: root.at.y + root.gap + root.height <= root.area_height ? root.at.y + root.gap : root.at.y - root.gap - root.height

    Rectangle {
        visible: !root.skinned
        anchors.fill: parent
        radius: Style.frame_radius
        color: Style.frame_color
        border.width: Math.max(1, Style.frame_border_width)
        border.color: Style.frame_border_color
    }

    Loader {
        id: skin_loader
        readonly property string name: Style.picker_skin
        onNameChanged: skin_loader.load()
        Component.onCompleted: skin_loader.load()

        function load() {
            if (skin_loader.name === "") {
                skin_loader.source = "";
                return;
            }
            skin_loader.setSource(Qt.resolvedUrl("loupe/" + skin_loader.name.charAt(0).toUpperCase() + skin_loader.name.slice(1) + ".qml"), {
                loupe: Qt.binding(() => root)
            });
        }
    }

    LoupeLens {
        visible: !root.skinned
        loupe: root
        x: root.pad
        y: root.pad
    }

    LoupeReadout {
        id: swatch_row
        loupe: root
        visible: !root.own_readout && root.pixel_mode
        opacity: root.skinned ? 0 : 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: coords.top
        anchors.bottomMargin: 2
    }

    Text {
        id: coords
        visible: !root.skinned
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.pad - 2
        text: Math.round(root.screen_x + root.at.x) + ", " + Math.round(root.screen_y + root.at.y) + "  " + root.zoom + "x"
        color: Style.text_fg
        font.family: Style.mono_font
        font.pixelSize: Style.fs(-4)
    }
}
