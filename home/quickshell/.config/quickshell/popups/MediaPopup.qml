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
import "../components/ps1" as Ps1

Popup {
    id: root

    popup_name: "media"
    size_class: "large"
    preferred_width: 520
    body_height: content.implicitHeight + 24
    key_help: "Tab player · space play · h/l seek · H/L track · s shuffle · r loop · q close"

    readonly property var player: MediaState.active
    readonly property var players: MediaState.players
    cursor_state: root.player_index(root.player)
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

    function handle_key(event) {
        const before = root.cursor_key();
        if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
            MediaState.step_player(-1);
            root.play_if_moved(before);
            event.accepted = true;
        } else if (event.key === Qt.Key_Tab) {
            MediaState.step_player(1);
            root.play_if_moved(before);
            event.accepted = true;
        } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            MediaState.toggle();
            ThemeAudio.play("confirm");
            event.accepted = true;
        } else if (event.key === Qt.Key_H) {
            if (event.modifiers & Qt.ShiftModifier) MediaState.previous();
            else MediaState.seek_by(-5);
            ThemeAudio.play((event.modifiers & Qt.ShiftModifier) ? "confirm" : "cursor");
            event.accepted = true;
        } else if (event.key === Qt.Key_L) {
            if (event.modifiers & Qt.ShiftModifier) MediaState.next();
            else MediaState.seek_by(5);
            ThemeAudio.play((event.modifiers & Qt.ShiftModifier) ? "confirm" : "cursor");
            event.accepted = true;
        } else if (event.key === Qt.Key_S) {
            MediaState.toggle_shuffle();
            ThemeAudio.play("confirm");
            event.accepted = true;
        } else if (event.key === Qt.Key_R) {
            MediaState.cycle_loop();
            ThemeAudio.play("confirm");
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
                sourceSize.width: Math.ceil(width / 2)
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

                Media.AlbumArt {
                    Layout.preferredWidth: 168
                    Layout.preferredHeight: 168
                    Layout.alignment: Qt.AlignTop
                    source: root.player ? root.player.trackArtUrl : ""
                    has_art: root.has_art
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
                        color: Style.pal.bg_surface

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
                        color: Style.pal.fg
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
                                color: Style.pal.fg_strong
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
                        color: Style.pal.primary
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
                    Media.SeekBar {
                        id: seek_bar
                        player: root.player
                    }

                    Loader {
                        active: root.cd
                        visible: active
                        Layout.fillWidth: true
                        sourceComponent: Ps1.CdTransport {
                            player: root.player
                            time_text: root.player ? root.fmt_time(root.player.position) : "0:00"
                            length_text: seek_bar.has_length ? root.fmt_time(seek_bar.track_length) : ""
                            onPrevious: MediaState.previous()
                            onNext: MediaState.next()
                            onToggle: MediaState.toggle()
                            onShuffle: MediaState.toggle_shuffle()
                            onLoop: MediaState.cycle_loop()
                        }
                    }

                    RowLayout {
                        visible: !root.cd
                        Layout.fillWidth: true
                        Layout.preferredHeight: 14

                        Text {
                            visible: seek_bar.has_length
                            text: root.player ? root.fmt_time(root.player.position) : "0:00"
                            color: Style.text_dim
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: seek_bar.has_length ? root.fmt_time(seek_bar.track_length) : "Live"
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
                            onActivated: MediaState.toggle_shuffle()
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
                            onActivated: MediaState.cycle_loop()
                        }
                    }

                    // --- Subtle cava visualizer along the bottom edge ---
                    Media.CavaStrip {}
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
                            onClicked: {
                                MediaState.select(player_chip.modelData);
                                ThemeAudio.play("cursor");
                            }
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
