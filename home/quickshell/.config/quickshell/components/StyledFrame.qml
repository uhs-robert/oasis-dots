// home/quickshell/.config/quickshell/components/StyledFrame.qml
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "../theme"

// The style's frame stack: fill, glass, glow, shade, custom frame, inset, sheen, effects layer, scanlines and dither.
Item {
    id: root

    required property var st
    property real radius: 0
    property real top_left_radius: root.radius
    property real top_right_radius: root.radius
    property real bottom_radius: root.radius
    // The top radius of the inset ring, custom frame and dither.
    property real inner_top_radius: root.radius
    property real inset_top_offset: 0
    property color island_color: root.st.frame_color
    property bool clear_fill: false
    property bool clear_border: false
    property bool glow_fit_height: true
    property real visor_top_cut: 6
    property bool sheen_on: root.st.frame_float > 0
    property color tint_color: root.st.pal.primary_light
    property bool device: false

    default property alias content: glow_layer.data
    property alias decor: decor_item.data
    property alias overlay: overlay_item.data
    readonly property alias layer_item: glow_layer

    readonly property color fill_color: root.st.frame_chamfer > 0 || root.st.frame_visor || root.st.custom_frame || root.clear_fill ? "transparent" : root.st.frame_follows_island ? root.island_color : root.st.frame_color
    readonly property real border_width: root.st.frame_visor || root.st.frame_chamfer > 0 || root.st.custom_frame || root.clear_border ? 0 : root.st.frame_border_width
    // Explicit corner radii antialias differently from `radius` at fractional scales.
    property bool corner_radii: root.top_left_radius !== root.radius || root.top_right_radius !== root.radius || root.bottom_radius !== root.radius

    Rectangle {
        visible: !root.corner_radii
        anchors.fill: parent
        color: root.fill_color
        radius: root.radius
        border.width: root.border_width
        border.color: root.st.frame_border_color
    }

    Rectangle {
        visible: root.corner_radii
        anchors.fill: parent
        color: root.fill_color
        topLeftRadius: root.top_left_radius
        topRightRadius: root.top_right_radius
        bottomLeftRadius: root.bottom_radius
        bottomRightRadius: root.bottom_radius
        border.width: root.border_width
        border.color: root.st.frame_border_color
    }

    VisorGlass {
        anchors.fill: parent
        top_cut: root.visor_top_cut
    }

    Shape {
        id: frame_glow
        visible: root.st.frame_glow.a > 0
        anchors.fill: parent
        anchors.margins: root.st.frame_border_width

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: frame_glow.width / 2
                centerY: 0
                focalX: frame_glow.width / 2
                focalY: 0
                centerRadius: root.glow_fit_height ? Math.max(frame_glow.width * 0.6, Math.min(frame_glow.height, 420)) : frame_glow.width * 0.6
                focalRadius: 0
                GradientStop { position: 0; color: root.st.frame_glow }
                GradientStop { position: 0.72; color: root.st.frame_color }
            }
            PathRectangle { width: frame_glow.width; height: frame_glow.height }
        }
    }

    FrameShade {
        anchors.fill: parent
        anchors.margins: root.st.frame_border_width
        st: root.st
        top_left_radius: Math.max(0, root.top_left_radius - root.st.frame_border_width)
        top_right_radius: Math.max(0, root.top_right_radius - root.st.frame_border_width)
        bottom_radius: Math.max(0, root.bottom_radius - root.st.frame_border_width)
        chamfer: root.st.frame_chamfer
    }

    CustomFrame {
        anchors.fill: parent
        st: root.st
        device: root.device
        top_radius: root.inner_top_radius
        bottom_radius: root.bottom_radius
    }

    FrameInset {
        st: root.st
        top_radius: root.inner_top_radius
        bottom_radius: root.bottom_radius
        top_offset: root.inset_top_offset
    }

    Sheen {
        color_top: root.sheen_on ? root.st.sheen : "transparent"
        corner: root.top_left_radius
        edge: root.st.frame_border_width
    }

    Item {
        id: decor_item
        anchors.fill: parent
    }

    // Everything drawn on the frame; styles with a glow or text shadow render it as one layer.
    Item {
        id: glow_layer
        readonly property bool layered: root.st.glow || root.st.text_shadow.a > 0
        anchors.fill: parent
        layer.enabled: glow_layer.layered
        opacity: glow_layer.layered ? 0 : 1
    }

    // Loaders rebuild the effects per style; MultiEffects left hidden across a style switch stopped drawing.
    Loader {
        anchors.fill: glow_layer
        active: root.st.glow
        sourceComponent: Item {
            MultiEffect {
                anchors.fill: parent
                source: glow_layer
                autoPaddingEnabled: false
                blurEnabled: true
                blur: 0.5
                blurMax: 12
                brightness: 0.2
                colorization: 1
                colorizationColor: root.st.glow_color
            }

            MultiEffect {
                anchors.fill: parent
                source: glow_layer
                autoPaddingEnabled: false
                colorization: root.st.glow_tint
                colorizationColor: root.tint_color
            }
        }
    }

    Loader {
        anchors.fill: glow_layer
        active: !root.st.glow && root.st.text_shadow.a > 0
        sourceComponent: MultiEffect {
            source: glow_layer
            autoPaddingEnabled: false
            shadowEnabled: true
            shadowBlur: 0
            shadowOpacity: 1
            shadowColor: root.st.text_shadow
            shadowHorizontalOffset: 2
            shadowVerticalOffset: 2
        }
    }

    Scanlines {
        visible: root.st.scanlines && root.st.frame_octagon <= 0
        anchors.fill: parent
        anchors.margins: root.radius > 0 ? root.st.frame_border_width : 0
        color: root.st.scanline_color
        period: root.st.scanline_period
    }

    Dither {
        anchors.fill: parent
        anchors.margins: root.st.frame_border_width
        color: root.st.dither
        radius: root.bottom_radius
        top_radius: root.inner_top_radius
    }

    Item {
        id: overlay_item
        anchors.fill: parent
    }
}
