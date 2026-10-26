import QtQuick
import Quickshell.Services.Pipewire
import qs.core
import qs.theme
import qs.ui
import qs.features.media
import qs.features.popups
import qs.features.bar

// The one media module: a well with art, play/pause, text and a right side of cava or the track position. Hover opens
// the media popup, a click pins it. Cava.qml is this module with the right side fixed to cava.
BarModule {
    id: root
    module_name: "media"
    wash: false

    // Set by Cava.qml: the layout entry `cava` always draws cava, whatever right_side_mode says.
    property string alias_mode: ""
    // Set by Bar.qml in the split island mode, where the strip already draws the cava: overrides everything.
    property string forced_right_side: ""

    readonly property var player: MediaState.active
    readonly property bool has_track: !!root.player && ((root.player.trackTitle || "") !== "" || (root.player.trackArtist || "") !== "")
    readonly property string wanted_right: root.forced_right_side !== "" ? root.forced_right_side : root.alias_mode !== "" ? root.alias_mode : MediaSettings.right_side_mode
    readonly property string right_mode: root.wanted_right === "cava" && !PowerSource.on_ac ? MediaSettings.battery_fallback : root.wanted_right

    // A side bar keeps its cava as the tail on the clock island, so the cava entry has no slot there; media shows as art and a button.
    shown: root.has_track && !(root.vertical && root.alias_mode !== "")
    implicitWidth: shown ? well.implicitWidth : 0
    implicitHeight: shown ? well.implicitHeight : 0

    HoverPopup {
        id: hover_popup
        popup_name: "media"
        module: root
        enabled: root.shown
        open_delay: 300
        close_grace: 250
    }

    WheelStepper {
        id: volume_stepper
    }

    WheelStepper {
        id: seek_stepper
    }

    PwObjectTracker {
        objects: MediaSettings.scroll_action === "volume_seek" ? [Pipewire.defaultAudioSink].filter(o => o) : []
    }

    readonly property var sink: Pipewire.defaultAudioSink

    readonly property int seek_seconds_per_notch: 5

    function scroll(wheel) {
        const effect = MediaSettings.scroll_effect(wheel.x >= well.right_left);
        if (effect === "seek") {
            const notches = seek_stepper.consume_event(wheel);
            if (notches !== 0) MediaState.seek_by(notches * root.seek_seconds_per_notch);
        } else if (effect === "skip") {
            const notches = volume_stepper.consume_event(wheel);
            if (notches > 0) MediaState.next();
            else if (notches < 0) MediaState.previous();
        } else if (effect === "volume" && root.sink && root.sink.ready && root.sink.audio) {
            const current = Math.round(root.sink.audio.volume * 100);
            const pct = volume_stepper.step_level(wheel, null, current, 0, 100);
            if (pct !== current) root.sink.audio.volume = pct / 100;
        }
    }

    // Under the well's own button, so the button's click wins.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) MediaState.toggle();
            else hover_popup.click();
        }
        onWheel: wheel => root.scroll(wheel)
    }

    MediaWell {
        id: well
        vertical: root.vertical
        cell: Math.max(16, Math.min(root.cross - 8, 28))
        width: root.vertical ? implicitWidth : parent.width
        height: root.vertical ? implicitHeight : Math.max(20, Math.min(root.bar_height - 6, 30))
        anchors.centerIn: parent
        player: root.player
        active: root.shown
        right_mode: root.right_mode
        show_title: MediaSettings.show_title
        show_artist: MediaSettings.show_artist
        text_layout: MediaSettings.text_layout
        max_chars: MediaSettings.max_chars
        text_scroll: MediaSettings.text_scroll
        text_scroll_speed: MediaSettings.text_scroll_speed
        compact: root.compact
        onToggle_requested: MediaState.toggle()
    }
}
