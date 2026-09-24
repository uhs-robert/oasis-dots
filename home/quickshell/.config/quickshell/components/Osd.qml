// home/quickshell/.config/quickshell/components/Osd.qml
import QtQuick
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
    property bool wanted: false
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

    readonly property string glyph: {
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

    function show(new_kind, new_level, new_muted) {
        root.kind = new_kind;
        root.level = Math.max(0, Math.min(1, new_level));
        root.muted = new_muted;
        if (!root.visible) {
            const mon = Hyprland.focusedMonitor;
            root.held_screen_name = mon ? mon.name : "";
        }
        root.wanted = true;
        root.reveal = 1;
        hide_timer.restart();
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
            root.wanted = false;
            root.reveal = 0;
        }
    }

    TextMetrics {
        id: percent_metrics
        font.family: Style.font_family
        font.pixelSize: Style.font_size
        text: "100%"
    }

    Rectangle {
        id: frame

        readonly property int pad_x: Style.px(16)
        readonly property int pad_y: Style.px(10)
        readonly property real header_height: title_tab.visible ? title_tab.height : 0

        y: root.slide * (1 - root.reveal)
        opacity: root.reveal
        width: Math.max(body.implicitWidth + pad_x * 2, title_tab.visible ? title_tab.width : 0)
        height: header_height + body.implicitHeight + pad_y * 2
        radius: Style.rounded ? height / 2 : Style.frame_radius
        color: Style.frame_follows_island ? Theme.bg_core : Style.frame_color
        border.width: Style.frame_border_width
        border.color: Style.frame_border_color

        Rectangle {
            id: title_tab
            visible: Style.show_title
            width: title_text.implicitWidth + 20
            height: title_text.implicitHeight + 4
            color: Style.title_bg

            Text {
                id: title_text
                anchors.centerIn: parent
                text: root.kind.toUpperCase()
                color: Style.title_fg
                font.family: Style.font_family
                font.pixelSize: Style.font_size - 2
                font.bold: true
                font.letterSpacing: 2
            }
        }

        RowLayout {
            id: body
            x: frame.pad_x
            y: frame.header_height + frame.pad_y
            spacing: Style.px(10)

            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Theme.glyph_size + 4
                horizontalAlignment: Text.AlignHCenter
                text: root.glyph
                color: Theme.theme_primary
                opacity: root.muted ? 0.5 : 1
                font.family: Theme.font_family
                font.pixelSize: Theme.glyph_size
            }

            Meter {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Style.px(180)
                value: root.level
                hot_from: 0.9
                opacity: root.muted ? 0.35 : 1
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: percent_metrics.width
                horizontalAlignment: Text.AlignRight
                text: root.percent + "%"
                color: root.muted ? Theme.fg_muted : Theme.fg_core
                font.family: Style.font_family
                font.pixelSize: Style.font_size
            }
        }
    }
}
