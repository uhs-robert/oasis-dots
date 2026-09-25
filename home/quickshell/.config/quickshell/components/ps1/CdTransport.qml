// home/quickshell/.config/quickshell/components/ps1/CdTransport.qml
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import "../../theme"

// The PS1 CD Player's readout and transport: TRACK and TIME in 7-segment digits over a glyph button row.
ColumnLayout {
    id: root

    property var player: null
    property string time_text: "0:00"
    property string length_text: ""
    signal previous()
    signal next()
    signal toggle()
    signal shuffle()
    signal loop()

    readonly property bool playing: !!root.player && root.player.isPlaying
    readonly property var track_no: {
        const m = root.player ? root.player.metadata : null;
        const n = m ? Number(m["xesam:trackNumber"]) : 0;
        return n > 0 ? String(n).padStart(2, "0") : "--";
    }

    spacing: 6

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: readout.implicitHeight + 10
        radius: 4
        color: Qt.alpha(Theme.bg_shadow, 0.55)
        border.width: 1
        border.color: Qt.alpha(Theme.blue, 0.55)

        RowLayout {
            id: readout
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            Text {
                text: "TRACK"
                color: Theme.theme_primary_light
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }

            Digits {
                text: root.track_no
                size: Style.font_size
                color: Theme.blue
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "TIME"
                color: Theme.theme_primary_light
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }

            Digits {
                text: root.time_text
                size: Style.font_size
                color: Theme.blue
            }

            Text {
                visible: root.length_text !== ""
                text: "/ " + root.length_text
                color: Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
            }
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
            model: [
                { glyph: "◀◀", lit: false, on: !!root.player && root.player.canGoPrevious, act: "previous" },
                { glyph: "▶", lit: root.playing, on: !!root.player && root.player.canTogglePlaying, act: "play" },
                { glyph: "■", lit: !!root.player && !root.playing, on: !!root.player && root.player.canTogglePlaying, act: "pause" },
                { glyph: "▶▶", lit: false, on: !!root.player && root.player.canGoNext, act: "next" },
                { glyph: "SHUFFLE", lit: !!root.player && root.player.shuffle, on: !!root.player && root.player.shuffleSupported, act: "shuffle" },
                { glyph: root.player && root.player.loopState === MprisLoopState.Track ? "REPEAT 1" : "REPEAT", lit: !!root.player && root.player.loopState !== MprisLoopState.None, on: !!root.player && root.player.loopSupported, act: "loop" }
            ]

            BiosPanel {
                id: button
                required property var modelData
                visible: button.modelData.on || button.modelData.glyph.length <= 2
                opacity: button.modelData.on ? 1 : 0.4
                lit: button.modelData.lit
                radius: 3
                implicitWidth: Math.max(Style.px(30), glyph_text.implicitWidth + 14)
                implicitHeight: Style.px(24)

                Text {
                    id: glyph_text
                    anchors.centerIn: parent
                    text: button.modelData.glyph
                    color: button.modelData.lit ? Theme.fg_strong : Style.text_fg
                    font.family: Style.font_family
                    font.pixelSize: button.modelData.glyph.length > 2 ? Style.fs(-6) : Style.fs(-4)
                    style: Text.Raised
                    styleColor: Style.text_shadow
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: button.modelData.on
                    onClicked: {
                        const a = button.modelData.act;
                        if (a === "previous") root.previous();
                        else if (a === "next") root.next();
                        else if (a === "shuffle") root.shuffle();
                        else if (a === "loop") root.loop();
                        else if ((a === "play") !== root.playing) root.toggle();
                    }
                }
            }
        }
    }
}
