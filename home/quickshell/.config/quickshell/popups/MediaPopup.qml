// home/quickshell/.config/quickshell/popups/MediaPopup.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import "../components"
import "../theme"
import "../services"
import "media" as Media
import "weather" as Weather
import "snes" as Snes
import "../components/ps1" as Ps1
import "../components/ps2" as Ps2

Popup {
    id: root

    popup_name: "media"
    size_class: "large"
    preferred_width: 520
    body_height: content.implicitHeight + 24
    key_help: "Tab player · space play · h/l seek · H/L track · s shuffle · r loop · q close"

    readonly property var player: MediaState.active
    readonly property var players: MediaState.players
    readonly property bool has_art: !!root.player && root.player.trackArtUrl !== ""
    readonly property bool ps2: Style.console_views === "ps2"

    // The PS1 CD Player transport under the progress bar.
    readonly property bool cd: root.st.console_views === "ps1"
    readonly property bool is_open: Popups.open_name === "media"
    onIs_openChanged: MediaState.tracking = root.is_open

    function fmt_time(seconds) {
        const s = Math.max(0, Math.floor(seconds || 0));
        const m = Math.floor(s / 60);
        const r = s % 60;
        return m + ":" + (r < 10 ? "0" + r : "" + r);
    }

    function player_index(p) {
        return root.players.indexOf(p);
    }

    function step_player(delta) {
        if (root.players.length === 0) return;
        const idx = root.player_index(root.player);
        const next_idx = (idx + delta + root.players.length) % root.players.length;
        MediaState.select(root.players[next_idx]);
    }

    function seek_ratio(ratio) {
        if (!root.player || !root.player.canSeek || !root.player.positionSupported) return;
        const length = MediaState.length_of(root.player);
        root.player.position = Math.max(0, Math.min(length, ratio * length));
    }

    function toggle_shuffle() {
        if (!root.player || !root.player.shuffleSupported) return;
        root.player.shuffle = !root.player.shuffle;
    }

    // Cycles None -> Playlist -> Track -> None.
    function cycle_loop() {
        if (!root.player || !root.player.loopSupported) return;
        const cur = root.player.loopState;
        if (cur === MprisLoopState.None) root.player.loopState = MprisLoopState.Playlist;
        else if (cur === MprisLoopState.Playlist) root.player.loopState = MprisLoopState.Track;
        else root.player.loopState = MprisLoopState.None;
    }

    function handle_key(event) {
        if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
            root.step_player(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Tab) {
            root.step_player(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            MediaState.toggle();
            event.accepted = true;
        } else if (event.key === Qt.Key_H) {
            if (event.modifiers & Qt.ShiftModifier) MediaState.previous();
            else MediaState.seek_by(-5);
            event.accepted = true;
        } else if (event.key === Qt.Key_L) {
            if (event.modifiers & Qt.ShiftModifier) MediaState.next();
            else MediaState.seek_by(5);
            event.accepted = true;
        } else if (event.key === Qt.Key_S) {
            root.toggle_shuffle();
            event.accepted = true;
        } else if (event.key === Qt.Key_R) {
            root.cycle_loop();
            event.accepted = true;
        }
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        implicitHeight: main_column.implicitHeight
        focus: true

        Keys.onPressed: event => root.handle_key(event)
        Keys.onTabPressed: event => root.handle_key(event)
        Keys.onBacktabPressed: event => root.handle_key(event)

        // --- Backdrop: the album art, heavily blurred and dimmed, tinting the panel ---
        Item {
            id: backdrop
            anchors.fill: parent
            clip: true
            z: 0

            Image {
                id: backdrop_art
                anchors.fill: parent
                visible: false
                source: root.has_art ? root.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                layer.enabled: true
            }

            MultiEffect {
                anchors.fill: parent
                anchors.margins: -32
                visible: root.has_art && backdrop_art.status === Image.Ready
                source: backdrop_art
                blurEnabled: true
                blur: 1.0
                blurMax: 64
                opacity: 0.2
            }
        }

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 10
            z: 1

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                Item {
                    id: art_container
                    Layout.preferredWidth: 168
                    Layout.preferredHeight: 168
                    Layout.alignment: Qt.AlignTop

                    Rectangle {
                        id: art_shadow_source
                        anchors.fill: parent
                        radius: Style.radius(12)
                        color: Theme.bg_shadow
                        visible: false
                        layer.enabled: true
                    }

                    MultiEffect {
                        anchors.fill: parent
                        anchors.topMargin: 8
                        visible: art_image.has_art && art_image.status === Image.Ready
                        source: art_shadow_source
                        blurEnabled: true
                        blur: 0.6
                        blurMax: 32
                        opacity: 0.55
                        z: -1
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.radius(12)
                        color: Theme.bg_surface
                        visible: !art_image.has_art || art_image.status !== Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !art_image.has_art || art_image.status !== Image.Ready
                        text: "\u{f001}"
                        color: Style.text_dim
                        font.family: Style.font_family
                        font.pixelSize: 48
                    }

                    Rectangle {
                        id: art_mask
                        anchors.fill: parent
                        radius: Style.radius(12)
                        visible: false
                        layer.enabled: true
                    }

                    Image {
                        id: art_image
                        readonly property bool has_art: root.has_art
                        anchors.fill: parent
                        visible: false
                        source: root.player ? root.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        layer.enabled: true
                    }

                    MultiEffect {
                        anchors.fill: parent
                        visible: art_image.has_art && art_image.status === Image.Ready
                        source: art_image
                        maskEnabled: true
                        maskSource: art_mask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 4

                    // --- Player identity pill ---
                    Rectangle {
                        Layout.alignment: Qt.AlignLeft
                        visible: !!root.player
                        implicitWidth: pill_label.implicitWidth + 16
                        implicitHeight: 20
                        radius: Style.radius(10)
                        color: Theme.bg_surface

                        Text {
                            id: pill_label
                            anchors.centerIn: parent
                            text: root.player ? (root.player.identity || "Player") : ""
                            color: Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                        }
                    }

                    Text {
                        visible: Style.console_views !== "nes"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: root.player ? (root.player.trackTitle || "Unknown title") : "Nothing playing"
                        color: Theme.fg_core
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(5)
                        font.weight: root.ps2 ? Font.ExtraLight : Font.Bold
                    }

                    Loader {
                        active: Style.console_views === "nes"
                        visible: active
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        sourceComponent: Weather.DqWindow {
                            implicitHeight: dq_title.implicitHeight + 24

                            Text {
                                id: dq_title
                                anchors.fill: parent
                                anchors.margins: 12
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                text: root.player ? (root.player.trackTitle || "Unknown title") : "Nothing playing"
                                color: Theme.fg_strong
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(2)
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        visible: root.player && root.player.trackArtist !== ""
                        text: root.player ? root.player.trackArtist : ""
                        color: Theme.theme_primary
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size
                        font.weight: root.ps2 ? Font.Light : Font.Normal
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        visible: root.player && root.player.trackAlbum !== ""
                        text: root.player ? root.player.trackAlbum : ""
                        color: Style.text_dim
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                        font.weight: root.ps2 ? Font.Light : Font.Normal
                    }

                    Item { Layout.fillHeight: true }

                    // --- Progress bar: click or drag to seek ---
                    Item {
                        id: progress_item
                        Layout.fillWidth: true
                        Layout.preferredHeight: progress_item.sound_test ? 30 : 16

                        readonly property bool sound_test: Style.console_views === "snes"
                        readonly property real track_length: MediaState.length_of(root.player)
                        readonly property bool has_length: track_length > 0
                        readonly property real ratio: progress_item.has_length
                            ? Math.max(0, Math.min(1, root.player.position / progress_item.track_length)) : 0
                        readonly property bool knob_active: seek_area.containsMouse || seek_area.pressed

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 6
                            radius: Style.radius(3)
                            color: Theme.bg_surface
                            visible: progress_item.has_length && !Style.segmented_levels && !progress_item.sound_test
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * progress_item.ratio
                            height: 6
                            radius: Style.radius(3)
                            color: Theme.theme_primary
                            visible: progress_item.has_length && !Style.segmented_levels && !progress_item.sound_test
                        }

                        Meter {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: progress_item.has_length && Style.segmented_levels && !progress_art.item
                            segment_count: 40
                            implicitHeight: Style.console_views === "nes" ? 16 : Style.px(8)
                            value: progress_item.ratio
                        }

                        // Console progress art; its track_x/track_width, when set, bound the seek area.
                        Loader {
                            id: progress_art
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: progress_item.sound_test ? parent.height : implicitHeight
                            visible: progress_item.has_length || progress_item.sound_test
                            sourceComponent: ({ snes: snes_progress, ps2: ps2_progress })[Style.console_views] || null
                        }

                        Component {
                            id: snes_progress
                            Snes.SnesSoundTest {
                                ratio: progress_item.ratio
                                track: root.player && root.player.metadata ? String(root.player.metadata["xesam:trackNumber"] || "") : ""
                            }
                        }

                        Component {
                            id: ps2_progress
                            Ps2.SphereTrack {
                                sphere: Style.px(8)
                                value: progress_item.ratio
                            }
                        }

                        Rectangle {
                            id: knob
                            readonly property int base_size: 12
                            width: progress_item.knob_active ? base_size + 3 : base_size
                            height: width
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(0, Math.min(parent.width - width, parent.width * progress_item.ratio - width / 2))
                            color: Theme.theme_primary
                            visible: progress_item.has_length && !Style.segmented_levels && !progress_item.sound_test
                            opacity: progress_item.knob_active ? 1 : 0
                            border.width: 2
                            border.color: Theme.bg_core

                            Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: seek_area
                            readonly property var art: progress_art.item
                            x: art && art.track_x !== undefined ? art.track_x : 0
                            width: art && art.track_width !== undefined ? art.track_width : parent.width
                            height: parent.height
                            hoverEnabled: true
                            enabled: !!root.player && root.player.canSeek && root.player.positionSupported
                            onPressed: mouse => root.seek_ratio(mouse.x / width)
                            onPositionChanged: mouse => { if (pressed) root.seek_ratio(Math.max(0, Math.min(1, mouse.x / width))); }
                        }
                    }

                    Loader {
                        active: root.cd
                        visible: active
                        Layout.fillWidth: true
                        sourceComponent: Ps1.CdTransport {
                            player: root.player
                            time_text: root.player ? root.fmt_time(root.player.position) : "0:00"
                            length_text: progress_item.has_length ? root.fmt_time(progress_item.track_length) : ""
                            onPrevious: MediaState.previous()
                            onNext: MediaState.next()
                            onToggle: MediaState.toggle()
                            onShuffle: root.toggle_shuffle()
                            onLoop: root.cycle_loop()
                        }
                    }

                    RowLayout {
                        visible: !root.cd
                        Layout.fillWidth: true
                        Layout.preferredHeight: 14

                        Text {
                            visible: progress_item.has_length
                            text: root.player ? root.fmt_time(root.player.position) : "0:00"
                            color: Style.text_dim
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: progress_item.has_length ? root.fmt_time(progress_item.track_length) : "Live"
                            color: Style.text_dim
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                        }
                    }

                    // --- Transport controls: centered on the progress bar above ---
                    RowLayout {
                        visible: !root.cd
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 2
                        spacing: 10

                        Media.RoundButton {
                            visible: !!root.player && root.player.shuffleSupported
                            diameter: 32
                            icon: "\u{f04b3}"
                            active: !!root.player && root.player.shuffle
                            onActivated: root.toggle_shuffle()
                        }

                        Media.RoundButton {
                            diameter: 32
                            icon: "\u{f048}"
                            button_enabled: !!root.player && root.player.canGoPrevious
                            onActivated: MediaState.previous()
                        }

                        Media.RoundButton {
                            diameter: 44
                            primary: true
                            icon: root.player && root.player.isPlaying ? "\u{f04c}" : "\u{f04b}"
                            button_enabled: !!root.player && root.player.canTogglePlaying
                            onActivated: MediaState.toggle()
                        }

                        Media.RoundButton {
                            diameter: 32
                            icon: "\u{f051}"
                            button_enabled: !!root.player && root.player.canGoNext
                            onActivated: MediaState.next()
                        }

                        Media.RoundButton {
                            visible: !!root.player && root.player.loopSupported
                            diameter: 32
                            icon: (!!root.player && root.player.loopState !== MprisLoopState.None) ? "\u{f0456}" : "\u{f0457}"
                            active: !!root.player && root.player.loopState !== MprisLoopState.None
                            badge: (!!root.player && root.player.loopState === MprisLoopState.Track) ? "1" : ""
                            onActivated: root.cycle_loop()
                        }
                    }

                    // --- Subtle cava visualizer along the bottom edge ---
                    Item {
                        id: cava_strip
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18
                        Layout.topMargin: 4

                        readonly property int bar_count: 28
                        readonly property bool active: MediaState.playing

                        RowLayout {
                            anchors.fill: parent
                            spacing: 3

                            Repeater {
                                model: cava_strip.bar_count

                                Rectangle {
                                    id: cava_bar
                                    required property int index
                                    readonly property int src_index: Math.floor(cava_bar.index * CavaState.bar_count / cava_strip.bar_count)
                                    readonly property real level: CavaState.levels[cava_bar.src_index] || 0

                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignBottom
                                    height: cava_strip.active ? Math.max(2, cava_bar.level * 18) : 2
                                    radius: Style.radius(1)
                                    color: Theme.theme_primary
                                    opacity: cava_strip.active ? 0.25 : 0

                                    Behavior on height { NumberAnimation { duration: 90 } }
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                            }
                        }
                    }
                }
            }

            // --- Player picker pills, one per player ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.players.length > 1 ? 28 : 0
                visible: root.players.length > 1
                z: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: root.players

                        MenuTab {
                            id: player_chip
                            required property var modelData

                            base_radius: 12
                            label: player_chip.modelData.identity || "Player"
                            active: player_chip.modelData === root.player
                            font_size: Style.fs(-3)
                            onClicked: MediaState.select(player_chip.modelData)
                        }
                    }
                }
            }

            MenuFooter {
                Layout.fillWidth: true
                z: 1
                text: root.help_hint
            }
        }
    }
}
