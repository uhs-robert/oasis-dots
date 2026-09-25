// home/quickshell/.config/quickshell/components/Osd.qml
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import "../theme"
import "../services"

PanelWindow {
    id: root

    property string kind: "volume"
    property real level: 0
    property bool muted: false
    // The last change in percent points, for styles that show it.
    property int delta: 0
    // A level change takes the slot for its hide timer, then voxtype gets it back.
    property bool level_wanted: false
    property bool vox_wanted: false
    readonly property bool wanted: root.level_wanted || root.vox_wanted
    // Held through the hide animation so the frame does not switch content as it fades.
    property string content: "level"
    property string vox_phase: "recording"
    property real vox_started_ms: 0
    property real now_ms: 0
    property real reveal: 0
    property string held_screen_name: ""

    // Changes are ignored until a source has settled, so startup and sink switches stay quiet.
    property bool audio_armed: false
    property bool brightness_armed: false

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property int slide: Style.px(10)

    readonly property int percent: {
        const raw = Math.round(root.level * 100);
        const snapped = Math.round(raw / 5) * 5;
        return Math.abs(raw - snapped) <= 1 ? snapped : raw;
    }

    readonly property bool showing_vox: root.content === "voxtype"
    readonly property bool vox_recording: root.showing_vox && root.vox_phase === "recording"
    readonly property bool readout_layout: Style.osd_layout === "readout" && !root.showing_vox
    readonly property bool ring_layout: Style.osd_layout === "ring" && !root.showing_vox
    readonly property bool banded: Style.show_title && (Style.title_band.a > 0 || Style.title_strip.a > 0)
    readonly property bool hud_layout: Style.osd_layout === "hud" && !root.showing_vox

    readonly property string title: root.showing_vox ? root.vox_phase.toUpperCase() : root.kind.toUpperCase()

    readonly property string elapsed: {
        const secs = Math.max(0, Math.floor((root.now_ms - root.vox_started_ms) / 1000));
        return Math.floor(secs / 60) + ":" + String(secs % 60).padStart(2, "0");
    }

    readonly property string glyph: {
        if (root.showing_vox) return root.vox_recording ? "󰍬" : "󰔟";
        if (root.kind === "brightness") return "󰃠";
        if (root.muted) return "";
        if (root.level <= 0.33) return "";
        if (root.level <= 0.66) return "";
        return "";
    }

    screen: Quickshell.screens.find(s => s.name === root.held_screen_name) || null
    visible: root.wanted || root.reveal > 0
    anchors.bottom: true
    margins.bottom: Style.px(72)
    exclusiveZone: 0
    color: "transparent"
    implicitWidth: frame.width
    implicitHeight: frame.height + root.slide
    mask: Region {}
    WlrLayershell.namespace: "quickshell-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Behavior on reveal {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    function hold_screen() {
        if (root.visible) return;
        const mon = Hyprland.focusedMonitor;
        root.held_screen_name = mon ? mon.name : "";
    }

    function refresh() {
        if (root.level_wanted) root.content = "level";
        else if (root.vox_wanted) root.content = "voxtype";
        root.reveal = root.wanted ? 1 : 0;
    }

    function show(new_kind, new_level, new_muted) {
        const prev = root.kind === new_kind ? root.level : new_level;
        root.kind = new_kind;
        root.level = Math.max(0, Math.min(1, new_level));
        root.muted = new_muted;
        root.delta = Math.round(root.level * 100) - Math.round(prev * 100);
        root.hold_screen();
        root.level_wanted = true;
        root.refresh();
        hide_timer.restart();
    }

    function voxtype_changed() {
        const active = VoxtypeState.recording || VoxtypeState.transcribing;
        if (active) {
            if (VoxtypeState.recording && (!root.vox_wanted || root.vox_phase !== "recording")) {
                root.vox_started_ms = Date.now();
                root.now_ms = root.vox_started_ms;
            }
            if (!VoxtypeState.recording && root.vox_phase === "recording") root.now_ms = Date.now();
            root.vox_phase = VoxtypeState.recording ? "recording" : "transcribing";
            root.hold_screen();
        }
        root.vox_wanted = active;
        root.refresh();
    }

    function audio_changed() {
        if (!root.audio_armed || !root.sink || !root.sink.audio) return;
        root.show("volume", root.sink.audio.volume, root.sink.audio.muted);
    }

    function brightness_changed() {
        if (!root.brightness_armed || !Backlight.has_device) return;
        root.show("brightness", Backlight.percent / 100, false);
    }

    function arm_audio() {
        root.audio_armed = false;
        audio_arm.restart();
    }

    function arm_brightness() {
        root.brightness_armed = false;
        brightness_arm.restart();
    }

    onSinkChanged: root.arm_audio()

    Component.onCompleted: {
        root.arm_audio();
        root.arm_brightness();
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink].filter(o => o)
    }

    Connections {
        target: root.sink
        function onReadyChanged() { root.arm_audio(); }
    }

    Connections {
        target: root.sink ? root.sink.audio : null
        function onVolumeChanged() { root.audio_changed(); }
        function onMutedChanged() { root.audio_changed(); }
    }

    Connections {
        target: VoxtypeState
        function onStateChanged() { root.voxtype_changed(); }
    }

    Connections {
        target: Backlight
        function onHas_deviceChanged() { root.arm_brightness(); }
        function onPercentChanged() { root.brightness_changed(); }
    }

    Timer {
        id: audio_arm
        interval: 800
        onTriggered: root.audio_armed = true
    }

    Timer {
        id: brightness_arm
        interval: 1500
        onTriggered: root.brightness_armed = true
    }

    Timer {
        id: hide_timer
        interval: 1500
        onTriggered: {
            root.level_wanted = false;
            root.refresh();
        }
    }

    Timer {
        interval: 1000
        triggeredOnStart: true
        repeat: true
        running: root.vox_recording && root.visible
        onTriggered: root.now_ms = Date.now()
    }

    TextMetrics {
        id: percent_metrics
        font.family: Style.number_font
        font.pixelSize: root.hud_layout ? Style.font_size + 5 : Style.font_size
        font.bold: Style.number_font !== Style.font_family
        text: "100%"
    }

    // Fits in the slide room under the frame, so the window keeps its size.
    Rectangle {
        visible: Style.frame_drop > 0
        y: frame.y + Style.frame_drop
        width: frame.width
        height: frame.height
        radius: frame.radius
        color: Theme.bg_shadow
        opacity: frame.opacity
    }

    Rectangle {
        id: frame

        readonly property int pad_x: Style.px(16)
        readonly property int pad_y: Style.px(10)
        readonly property real top_rule: Style.frame_top_rule ? Style.accent_height : 0
        readonly property real band_height: Math.max(26, title_tab.height + 4)
        readonly property real header_height: !title_tab.visible ? 0 : root.banded ? frame.band_height + 4 + Style.inset_pad : title_tab.height + frame.top_rule + Style.inset_pad

        y: root.slide * (1 - root.reveal)
        opacity: root.reveal
        width: Math.max(body.implicitWidth + pad_x * 2, title_tab.visible ? title_tab.width + Style.inset_pad * 2 : 0)
        height: header_height + body.implicitHeight + pad_y * 2
        radius: Style.rounded && !Style.frame_visor ? height / 2 : Style.frame_radius
        color: Style.frame_chamfer > 0 || Style.frame_visor || Style.custom_frame ? "transparent" : Style.frame_follows_island ? Theme.bg_core : Style.frame_color
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
                    centerRadius: frame_glow.width * 0.6
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
        }

        Item {
            id: glow_layer
            readonly property bool layered: Style.glow || Style.text_shadow.a > 0
            anchors.fill: parent
            layer.enabled: glow_layer.layered
            opacity: glow_layer.layered ? 0 : 1


            Loader {
                active: root.banded
                x: Style.inset_pad + Style.frame_border_width
                y: x
                width: frame.width - x * 2
                height: frame.band_height
                sourceComponent: Style.title_strip.a > 0 ? osd_strip : osd_header

                Component {
                    id: osd_header
                    TabHeader {
                        readonly property var ids: Style.title_ids.osd || []
                        title: root.title
                        panel_id: ids[0] || ""
                        readout: ids[1] || ""
                    }
                }

                Component {
                    id: osd_strip
                    TitleStrip {
                        title: root.title
                        closable: false
                    }
                }
            }

            Rectangle {
                id: title_tab
                visible: Style.show_title
                opacity: root.banded ? 0 : 1
                x: (Style.fade_fills || Style.rounded ? frame.radius : 0) + Style.inset_pad
                y: (Style.fade_fills ? Style.frame_border_width : 0) + frame.top_rule + Style.inset_pad
                width: Style.fade_fills ? Math.max(title_text.implicitWidth + 20 + title_index.space, body.implicitWidth + frame.pad_x * 2 - frame.radius * 2) : title_text.implicitWidth + 20 + title_index.space
                height: Math.max(title_text.implicitHeight, title_index.space > 0 ? title_index.implicitHeight : 0) + 4
                color: Style.fade_fills ? "transparent" : Style.title_bg

                FadeFill {
                    visible: Style.fade_fills
                    fill: Style.title_bg
                }

                TitleIndex {
                    id: title_index
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.showing_vox ? "" : root.kind
                }

                Text {
                    id: title_text
                    anchors.centerIn: Style.fade_fills ? undefined : parent
                    anchors.horizontalCenterOffset: title_index.space / 2
                    x: 10 + title_index.space
                    y: (parent.height - height) / 2
                    text: Style.title_prefix + root.title + Style.title_suffix
                    color: Style.title_fg
                    font.family: Style.title_font_family
                    font.pixelSize: Style.font_size - 2
                    font.weight: Style.title_weight > 0 ? Style.title_weight : Style.title_font_family === Style.font_family ? Font.Bold : Font.Normal
                    font.letterSpacing: Style.title_spacing
                }
            }

            RowLayout {
                id: body
                x: frame.pad_x
                y: frame.header_height + frame.pad_y
                spacing: Style.px(10)

                Loader {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Style.px(84)
                    Layout.preferredHeight: Style.px(84)
                    Layout.rightMargin: Style.px(6)
                    active: root.ring_layout
                    visible: root.ring_layout
                    sourceComponent: RingGauge {
                        value: root.level
                        label: String(root.percent)
                        unit: "%"
                        opacity: root.muted ? 0.5 : 1
                    }
                }

                OsdReadout {
                    visible: root.readout_layout
                    level: root.level
                    percent: root.percent
                    muted: root.muted
                    delta: root.delta
                    label: root.kind === "brightness" ? "Backlight" : root.muted ? "Muted" : "\u25d6 " + (root.sink ? root.sink.description || root.sink.name : "")
                }

                Text {
                    visible: !root.readout_layout
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Theme.glyph_size + 4
                    horizontalAlignment: Text.AlignHCenter
                    text: root.glyph
                    color: !root.showing_vox ? Theme.theme_primary : root.vox_recording ? Theme.theme_label : Theme.warning
                    opacity: !root.showing_vox && root.muted ? 0.5 : 1
                    font.family: Theme.font_family
                    font.pixelSize: Theme.glyph_size
                }

                Item {
                    visible: !root.readout_layout
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: root.showing_vox ? Style.px(260) : Style.px(180)
                    Layout.preferredHeight: root.showing_vox ? Style.px(44) : meter.implicitHeight

                    Meter {
                        id: meter
                        visible: !root.showing_vox
                        width: parent.width
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.showing_vox ? 0 : root.level
                        hot_from: root.showing_vox ? 1 : 0.9
                        opacity: !root.showing_vox && root.muted ? 0.35 : 1
                    }

                    Waveform {
                        id: waveform
                        visible: root.showing_vox
                        anchors.fill: parent
                        frozen: !root.vox_recording
                        running: root.showing_vox && root.visible
                    }
                }

                Text {
                    visible: !root.readout_layout && !root.ring_layout
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: percent_metrics.width
                    horizontalAlignment: Text.AlignRight
                    text: root.showing_vox ? root.elapsed : root.percent + "%"
                    color: root.showing_vox && !root.vox_recording ? Theme.warning : !root.showing_vox && root.muted ? Style.text_muted : root.hud_layout ? Style.text_primary : Theme.fg_core
                    font.family: Style.number_font
                    font.pixelSize: percent_metrics.font.pixelSize
                    font.bold: Style.number_font !== Style.font_family
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

            Repeater {
                model: Style.scanlines && Style.frame_octagon <= 0 ? Math.max(0, Math.ceil(parent.height / 3)) : 0

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

        Rectangle {
            visible: Style.frame_top_rule
            x: frame.radius
            width: frame.width - frame.radius * 2
            height: frame.top_rule
            color: Style.accent_color
        }
    }
}
