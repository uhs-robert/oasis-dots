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
    readonly property int row_height: Style.px(22)
    readonly property int text_size: Style.font_size - 2
    readonly property real screen_width: root.screen ? root.screen.width : 1920
    readonly property real screen_height: root.screen ? root.screen.height : 1080

    // The payload's columns assume eww's row height, so add columns when this style's rows run taller.
    readonly property int columns: {
        const rows_fit = Math.max(1, Math.floor((root.screen_height * 0.85 - Style.px(120)) / root.row_height));
        const wanted_cols = Math.max(root.payload.columns || 1, Math.ceil(root.items.length / rows_fit));
        return Math.max(1, Math.min(4, wanted_cols));
    }
    readonly property string longest_key: root.items.reduce((a, item) => item.key.length > a.length ? item.key : a, "")
    readonly property real key_width: Math.max(key_metrics.height + 2, key_metrics.advanceWidth + 8)
    readonly property real desc_max_width: Math.max(Style.px(80), (root.screen_width * 0.9 - frame.pad_x * 2) / root.columns - root.key_width - Style.px(24))

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
    margins.top: root.gap
    margins.bottom: root.gap
    margins.left: root.gap
    margins.right: root.gap
    implicitWidth: frame.width
    implicitHeight: frame.height + Style.frame_drop
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
        id: key_metrics
        font.family: Style.font_family
        font.pixelSize: Style.font_size - 5
        font.bold: true
        text: root.longest_key
    }

    Rectangle {
        visible: Style.frame_drop > 0
        y: Style.frame_drop
        width: frame.width
        height: frame.height
        radius: frame.radius
        color: Theme.bg_shadow
    }

    Rectangle {
        id: frame

        readonly property int pad_x: Style.px(14)
        readonly property int pad_y: Style.px(8)
        readonly property real top_edge: Math.max(Style.accent_height, Style.frame_border_width)
        readonly property real title_x: Style.fade_fills || Style.rounded ? frame.radius : Style.frame_brackets.a > 0 ? 6 : 0
        // The inner ring's room below the accent line, which already covers the border.
        readonly property real ring_pad: Style.inset_pad > 0 ? Style.inset_pad - Style.frame_border_width : 0
        readonly property real header_height: title_tab.height + frame.ring_pad

        width: Math.max(body.implicitWidth + pad_x * 2, title_text.implicitWidth + 20 + title_x * 2 + Style.inset_pad * 2 + (readout.visible ? readout.implicitWidth + 16 : 0))
        height: top_edge + header_height + body.implicitHeight + pad_y * 2
        radius: Style.frame_radius
        color: Style.frame_chamfer > 0 || Style.frame_visor ? "transparent" : Style.frame_follows_island ? Theme.bg_mantle : Style.frame_color
        border.width: Style.frame_visor || Style.frame_chamfer > 0 ? 0 : Style.frame_border_width
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

        CornerBrackets {
            anchors.fill: parent
        }

        FrameInset {
            top_radius: frame.radius
            bottom_radius: frame.radius
            top_offset: frame.top_edge - Style.frame_border_width
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


            Rectangle {
                id: title_tab
                x: frame.title_x + Style.inset_pad
                y: frame.top_edge + frame.ring_pad
                width: Style.fade_fills ? frame.width - frame.title_x * 2 : title_text.implicitWidth + 20
                height: title_text.implicitHeight + 4
                color: Style.show_title && !Style.fade_fills ? Style.title_bg : "transparent"

                FadeFill {
                    visible: Style.show_title && Style.fade_fills
                    fill: Style.title_bg
                }

                Text {
                    id: title_text
                    x: 10
                    y: (parent.height - height) / 2
                    text: Style.title_prefix + root.title + (Style.caret_phase ? Style.title_suffix : " ".repeat(Style.title_suffix.length))
                    color: Style.show_title ? Style.title_fg : Style.accent_color
                    font.family: Style.title_font_family
                    font.pixelSize: Style.font_size - 2
                    font.bold: Style.title_font_family === Style.font_family
                    font.letterSpacing: Style.show_title ? Style.title_spacing : 0
                    style: Style.title_glow.a > 0 ? Text.Outline : Text.Normal
                    styleColor: Style.title_glow
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
                font.pixelSize: Style.font_size - 5
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

                            Layout.preferredWidth: root.key_width + Style.px(8) + desc_text.width
                            Layout.preferredHeight: root.row_height

                            KeyBadge {
                                anchors.verticalCenter: parent.verticalCenter
                                key: row.modelData.key
                            }

                            Text {
                                id: desc_text
                                x: root.key_width + Style.px(8)
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
            visible: Style.scanlines
            anchors.fill: parent

            Repeater {
                model: Style.scanlines ? Math.max(0, Math.ceil(parent.height / 3)) : 0

                Rectangle {
                    required property int index
                    y: index * 3
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
