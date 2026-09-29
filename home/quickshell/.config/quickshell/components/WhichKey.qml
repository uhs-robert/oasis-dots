// home/quickshell/.config/quickshell/components/WhichKey.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../theme"
import "../services"
import "neovim" as Neovim

// HyprVim's which-key HUD over its `hyprvim_whichkey` IPC target, drawn in the active style.
PanelWindow {
    id: root

    property var payload: ({})
    property bool wanted: false

    readonly property var items: root.payload.items || []
    readonly property string position: root.payload.position || "bottom-right"
    readonly property string title: {
        const t = root.payload.title || "";
        return Style.show_title ? t.toUpperCase() : t;
    }
    readonly property string footer_hint: (root.payload.footer || []).map(f => ({ ESC: "Esc", BS: "Backspace", RET: "Enter", TAB: "Tab", SPACE: "space" }[f.key] || f.key) + " " + f.desc).join(" · ")
    readonly property bool has_footer: Style.show_footer && root.footer_hint !== ""

    readonly property int gap: Style.px(18)
    readonly property int text_size: Style.whichkey_size > 0 ? Style.whichkey_size : Style.fs(-2)
    readonly property int key_size: Style.whichkey_size > 0 ? Style.whichkey_size : Style.fs(-5)
    readonly property int row_height: Math.max(Style.px(22), root.text_size + Style.px(8))
    readonly property real screen_width: root.screen ? root.screen.width : 1920
    readonly property real screen_height: root.screen ? root.screen.height : 1080

    // The payload's columns assume eww's row height, so add columns when this style's rows run taller.
    readonly property int columns: {
        const rows_fit = Math.max(1, Math.floor((root.screen_height * 0.85 - Style.px(120)) / root.row_height));
        const wanted_cols = Math.max(root.payload.columns || 1, Math.ceil(root.items.length / rows_fit));
        return Math.max(1, Math.min(4, wanted_cols));
    }
    readonly property string longest_key: root.items.reduce((a, item) => item.key.length > a.length ? item.key : a, "")
    readonly property real key_width: Style.controller !== "" ? Math.max(key_metrics.height + 2, key_measure.implicitWidth) : Math.max(key_metrics.height + 2, key_metrics.advanceWidth + 8)
    readonly property real arrow_space: Style.whichkey_arrow !== "" ? arrow_metrics.advanceWidth + Style.px(6) : 0
    readonly property real desc_max_width: Math.max(Style.px(80), (root.screen_width * 0.9 - frame.pad_x * 2) / root.columns - root.key_width - root.arrow_space - Style.px(24))

    screen: {
        const by_payload = Quickshell.screens.find(s => s.name === root.payload.screen);
        if (by_payload) return by_payload;
        const mon = Hyprland.focusedMonitor;
        return (mon && Quickshell.screens.find(s => s.name === mon.name)) || null;
    }
    visible: false
    color: "transparent"
    exclusiveZone: 0
    anchors.top: root.position.startsWith("top")
    anchors.bottom: root.position.startsWith("bottom")
    anchors.left: root.position.endsWith("left")
    anchors.right: root.position.endsWith("right")
    margins.top: root.gap - root.shadow_pad
    margins.bottom: root.gap - root.shadow_pad
    margins.left: root.gap - root.shadow_pad
    margins.right: root.gap - root.shadow_pad
    // Room on every side for a soft shadow, taken out of the gap so the frame stays put.
    readonly property int shadow_pad: Style.frame_shadow.a > 0 ? Math.min(Style.frame_drop, root.gap) : 0
    implicitWidth: frame.width + root.shadow_pad * 2
    // The header takes the bar's submap colour: fills get it under dark ink, plain titles take it as text.
    readonly property bool tinted: SubmapState.active || Style.bar_lualine
    readonly property color header_color: SubmapState.bar_color
    readonly property bool filled_title: Style.show_title && Style.title_bg.a > 0

    // Floating frames set the title chip into the top border, half of it above the frame.
    readonly property bool float_title: Style.border_title && Style.show_title
    readonly property real float_top: root.float_title ? Math.round(title_tab.height / 2) : 0
    implicitHeight: frame.height + (root.shadow_pad > 0 ? root.shadow_pad * 2 : Style.frame_drop) + root.float_top
    mask: Region {}
    WlrLayershell.namespace: "quickshell-whichkey"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    IpcHandler {
        target: "hyprvim_whichkey"

        function open(path: string): void {
            root.wanted = true;
            payload_file.path = path;
            payload_file.reload();
        }

        function close(): void {
            root.wanted = false;
            root.visible = false;
        }
    }

    FileView {
        id: payload_file
        printErrors: false
        onLoaded: {
            if (!root.wanted) return;
            try {
                root.payload = JSON.parse(text());
                root.visible = root.items.length > 0;
            } catch (e) {
                console.warn("WhichKey: invalid payload (" + e + ")");
            }
        }
    }

    TextMetrics {
        id: arrow_metrics
        font.family: Style.font_family
        font.pixelSize: root.text_size
        text: Style.whichkey_arrow
    }

    TextMetrics {
        id: key_metrics
        font.family: Style.mono_font
        font.pixelSize: root.key_size
        font.bold: Style.mono_font === Style.font_family
        text: root.longest_key
    }

    // Controller buttons change a badge's width, so the key column sizes from the badges as drawn.
    Column {
        id: key_measure
        opacity: 0
        enabled: false

        Repeater {
            model: Style.controller !== "" ? root.items : []

            KeyBadge {
                required property var modelData
                key: modelData.key
                desc: modelData.desc || ""
                font_px: Style.whichkey_size
            }
        }
    }

    Rectangle {
        visible: Style.frame_drop > 0 && Style.frame_shadow.a === 0
        y: frame.y + Style.frame_drop
        width: frame.width
        height: frame.height
        radius: frame.radius
        color: Theme.bg_shadow
    }

    Loader {
        active: Style.frame_shadow.a > 0
        x: frame.x + 4
        y: frame.y + 4
        width: frame.width - 8
        height: frame.height
        sourceComponent: RectangularShadow {
            blur: root.shadow_pad
            radius: frame.radius
            color: Style.frame_shadow
        }
    }

    Rectangle {
        id: frame
        x: root.shadow_pad
        y: root.shadow_pad + root.float_top

        readonly property int pad_x: Style.px(14)
        readonly property int pad_y: Style.px(8)
        readonly property real top_edge: Math.max(Style.accent_height, Style.frame_border_width)
        readonly property real title_x: Style.fade_fills || Style.rounded && !Style.title_case ? frame.radius : 0
        // The inner ring's room below the accent line, which already covers the border.
        readonly property real ring_pad: Style.inset_pad > 0 ? Style.inset_pad - Style.frame_border_width : 0
        readonly property bool banded: Style.show_title && (Style.title_band.a > 0 || Style.title_strip.a > 0)
        readonly property real band_height: Math.max(26, title_tab.height + 4)
        readonly property real header_height: frame.banded ? frame.band_height + 4 + Style.inset_pad : root.float_title ? root.float_top : title_tab.height + frame.ring_pad


        // Wide enough for the whole title in the header variant the style draws.
        readonly property real header_min: frame.banded ? (band_loader.item ? band_loader.item.min_width : 0) + (Style.inset_pad + Style.frame_border_width) * 2
            : root.float_title ? (border_loader.item ? border_loader.item.implicitWidth : 0) + 24
            : title_text.implicitWidth + 20 + title_x * 2 + Style.inset_pad * 2 + (readout.visible ? readout.implicitWidth + 16 : 0)
        width: Math.max(body.implicitWidth + pad_x * 2, frame.header_min) + Style.slant_room
        height: top_edge + header_height + body.implicitHeight + pad_y * 2 + Style.slant_room
        radius: Style.frame_radius
        color: Style.frame_chamfer > 0 || Style.frame_visor || Style.custom_frame ? "transparent" : Style.frame_follows_island ? Theme.bg_mantle : Style.frame_color
        border.width: Style.frame_visor || Style.frame_chamfer > 0 || Style.custom_frame ? 0 : Style.frame_border_width
        border.color: Style.frame_border_color

        VisorGlass {
            anchors.fill: parent
        }

        Shape {
            id: frame_glow
            visible: Style.frame_glow.a > 0
            anchors.fill: parent
            anchors.margins: Style.frame_border_width

            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: frame_glow.width / 2
                    centerY: 0
                    focalX: frame_glow.width / 2
                    focalY: 0
                    centerRadius: Math.max(frame_glow.width * 0.6, Math.min(frame_glow.height, 420))
                    focalRadius: 0
                    GradientStop { position: 0; color: Style.frame_glow }
                    GradientStop { position: 0.72; color: Style.frame_color }
                }
                PathRectangle { width: frame_glow.width; height: frame_glow.height }
            }
        }

        FrameShade {
            anchors.fill: parent
            anchors.margins: Style.frame_border_width
            top_radius: Math.max(0, frame.radius - Style.frame_border_width)
            bottom_radius: top_radius
            chamfer: Style.frame_chamfer
        }

        CustomFrame {
            anchors.fill: parent
        }

        FrameInset {
            top_radius: frame.radius
            bottom_radius: frame.radius
            top_offset: frame.top_edge - Style.frame_border_width
        }

        Sheen {
            color_top: Style.frame_float > 0 ? Style.sheen : "transparent"
            corner: frame.radius
            edge: Style.frame_border_width
        }

        Rectangle {
            x: frame.radius
            width: frame.width - frame.radius * 2
            height: Style.accent_height
            color: Style.accent_color
        }

        Item {
            id: glow_layer
            readonly property bool layered: Style.glow || Style.text_shadow.a > 0
            anchors.fill: parent
            layer.enabled: glow_layer.layered
            opacity: glow_layer.layered ? 0 : 1


            Loader {
                id: band_loader
                active: frame.banded
                x: Style.inset_pad + Style.frame_border_width
                y: x
                width: frame.width - x * 2
                height: frame.band_height
                sourceComponent: Style.title_strip.a > 0 ? key_strip : key_header

                Component {
                    id: key_header
                    TabHeader {
                        readonly property var ids: Style.title_ids.whichkey || []
                        accent: root.tinted ? root.header_color : "transparent"
                        title: root.title
                        panel_id: ids[0] || ""
                        readout: ids[1] || ""
                    }
                }

                Component {
                    id: key_strip
                    TitleStrip {
                        title: root.title
                        title_color: root.tinted ? root.header_color : "transparent"
                        closable: false
                    }
                }
            }

            Rectangle {
                id: title_tab
                opacity: frame.banded || root.float_title ? 0 : 1
                x: frame.title_x + Style.inset_pad
                y: frame.top_edge + frame.ring_pad
                width: Style.fade_fills ? frame.width - frame.title_x * 2 : title_text.implicitWidth + 20
                height: title_text.implicitHeight + 4
                color: !Style.show_title || Style.fade_fills ? "transparent" : root.tinted && root.filled_title ? root.header_color : Style.title_bg

                FadeFill {
                    visible: Style.show_title && Style.fade_fills
                    fill: root.tinted && root.filled_title ? Qt.alpha(root.header_color, Style.title_bg.a) : Style.title_bg
                }

                Text {
                    id: title_text
                    x: 10
                    y: (parent.height - height) / 2
                    text: Style.title_prefix + Style.title_text(root.title) + (Style.caret_phase ? Style.title_suffix : " ".repeat(Style.title_suffix.length))
                    color: !root.tinted ? (Style.show_title ? Style.title_fg : Style.accent_color) : !Style.show_title || !root.filled_title ? root.header_color : Style.fade_fills ? Style.title_fg : Theme.bg_crust
                    font.family: Style.title_font_family
                    font.pixelSize: Style.title_size > 0 ? Style.title_size : Style.fs(-2)
                    font.weight: Style.title_weight > 0 ? Style.title_weight : Style.title_font_family === Style.font_family ? Font.Bold : Font.Normal
                    font.letterSpacing: Style.show_title ? Style.title_spacing : 0
                }
            }

            Loader {
                id: border_loader
                active: root.float_title
                x: 12
                y: -root.float_top
                sourceComponent: Neovim.BorderTitle {
                    title: Style.title_text(root.title)
                    fill: root.tinted ? root.header_color : Style.title_bg
                    ink: root.tinted ? Theme.bg_crust : Style.title_fg
                }
            }

            Text {
                id: readout
                visible: Style.show_title && Style.title_readout !== ""
                anchors.right: parent.right
                anchors.rightMargin: frame.title_x + 10
                y: title_tab.y + (title_tab.height - height) / 2
                text: Style.title_readout.replace("{code}", root.title.slice(0, 3))
                color: Style.title_readout_fg.a > 0 ? Style.title_readout_fg : Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 1
            }

            ColumnLayout {
                id: body
                x: frame.pad_x
                y: frame.top_edge + frame.header_height + frame.pad_y
                spacing: Style.px(6)

                GridLayout {
                    columns: root.columns
                    columnSpacing: Style.px(24)
                    rowSpacing: 0

                    Repeater {
                        model: root.items

                        Item {
                            id: row
                            required property var modelData

                            Layout.preferredWidth: root.key_width + Style.px(8) + root.arrow_space + desc_text.width
                            Layout.preferredHeight: root.row_height

                            KeyBadge {
                                anchors.verticalCenter: parent.verticalCenter
                                key: row.modelData.key
                                desc: row.modelData.desc || ""
                                font_px: Style.whichkey_size
                            }

                            Text {
                                visible: root.arrow_space > 0
                                x: root.key_width + Style.px(5)
                                anchors.verticalCenter: parent.verticalCenter
                                text: Style.whichkey_arrow
                                color: Style.text_muted
                                font.family: Style.font_family
                                font.pixelSize: root.text_size
                            }

                            Text {
                                id: desc_text
                                x: root.key_width + Style.px(8) + root.arrow_space
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, root.desc_max_width)
                                elide: Text.ElideRight
                                text: row.modelData.desc
                                color: row.modelData.group ? Style.accent_color : Theme.fg_core
                                font.family: Style.font_family
                                font.pixelSize: root.text_size
                                font.bold: row.modelData.group === true
                            }
                        }
                    }
                }

                MenuFooter {
                    visible: root.has_footer
                    Layout.fillWidth: true
                    centered: true
                    text: root.footer_hint
                }
            }
        }

        // Rebuilt per style, as in Popup.qml: hidden MultiEffects stopped drawing after a style switch.
        Loader {
            anchors.fill: glow_layer
            active: Style.glow
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
                    colorizationColor: Style.glow_color
                }

                MultiEffect {
                    anchors.fill: parent
                    source: glow_layer
                    autoPaddingEnabled: false
                    colorization: Style.glow_tint
                    colorizationColor: Theme.theme_primary_light
                }
            }
        }

        Loader {
            anchors.fill: glow_layer
            active: !Style.glow && Style.text_shadow.a > 0
            sourceComponent: MultiEffect {
                source: glow_layer
                autoPaddingEnabled: false
                shadowEnabled: true
                shadowBlur: 0
                shadowOpacity: 1
                shadowColor: Style.text_shadow
                shadowHorizontalOffset: 2
                shadowVerticalOffset: 2
            }
        }

        Item {
            visible: Style.scanlines && Style.frame_octagon <= 0
            anchors.fill: parent
            anchors.margins: frame.radius > 0 ? Style.frame_border_width : 0

            Repeater {
                model: Style.scanlines && Style.frame_octagon <= 0 ? Math.max(0, Math.ceil(parent.height / Style.scanline_period)) : 0

                Rectangle {
                    required property int index
                    y: index * Style.scanline_period
                    width: parent.width
                    height: 1
                    color: Style.scanline_color
                }
            }
        }

        Dither {
            anchors.fill: parent
            anchors.margins: Style.frame_border_width
            color: Style.dither
            radius: frame.radius
            top_radius: frame.radius
        }
    }
}
