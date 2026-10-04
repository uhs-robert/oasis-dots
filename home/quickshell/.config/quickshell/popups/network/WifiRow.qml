// home/quickshell/.config/quickshell/popups/network/WifiRow.qml
import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import "../../components"
import "../../theme"
import "../../components/nes" as Nes
import "../../components/snes" as Snes
import "../../components/ps2" as Ps2
import "../../components/goldeneye" as Goldeneye
import "Network.js" as Net

MenuRow {
    id: root

    required property var modelData
    required property int index

    property var popup_st
    property bool link_watch: false
    property bool codec: false
    property bool ps2: false

    readonly property bool is_advanced: !!root.modelData.advanced

    signal activated()

    height: Style.px(24)

    Loader {
        active: root.ps2
        anchors.fill: parent
        z: -1
        sourceComponent: Ps2.Block {
            selected: root.selected
            radius: 4
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 6 + root.inset
        anchors.rightMargin: 6 + root.key_space
        spacing: 6

        // NES signal art in place of the glyph; SNES puts its gauge at the row's end.
        Loader {
            id: signal_art
            readonly property Component view: ({ nes: nes_signal })[root.popup_st.console_views] || null
            active: !root.is_advanced && !!view
            visible: active
            sourceComponent: view

            Component {
                id: nes_signal
                Nes.CoinMeter {
                    size: 12
                    value: root.modelData.signalStrength || 0
                }
            }
        }

        Goldeneye.SegmentStrip {
            visible: root.link_watch && !root.is_advanced
            value: root.modelData.signalStrength || 0
        }

        Text {
            visible: !root.is_advanced && !signal_art.active && root.popup_st.console_views !== "snes" && !root.link_watch
            text: Net.signal_glyph(root.modelData.signalStrength || 0)
            color: root.fg(root.modelData.connected ? root.popup_st.text_primary : root.popup_st.text_fg)
            font.family: root.popup_st.font_family
            font.pixelSize: root.popup_st.fs(-1)
        }

        RowLabel {
            Layout.fillWidth: true
            elide: Text.ElideRight
            label: root.is_advanced ? "Advanced…" : root.modelData.name
            color: root.fg(root.modelData.connected ? root.popup_st.text_accent : root.popup_st.text_fg)
            font.family: root.popup_st.font_family
            font.pixelSize: root.popup_st.fs(-1)
        }

        Text {
            visible: (root.codec || root.popup_st.console_views === "nes") && !root.is_advanced
            text: Math.round((root.modelData.signalStrength || 0) * 100) + "%"
            color: root.fg(root.popup_st.text_muted)
            font.family: root.popup_st.font_family
            font.pixelSize: root.popup_st.fs(-3)
        }

        Text {
            visible: !root.is_advanced && root.modelData.security !== WifiSecurityType.Open
            text: ""
            color: root.fg(root.popup_st.text_muted)
            font.family: root.popup_st.font_family
            font.pixelSize: root.popup_st.fs(-2)
        }

        Text {
            visible: !root.is_advanced && root.modelData.known
            text: ""
            color: root.fg(root.popup_st.text_muted)
            font.family: root.popup_st.font_family
            font.pixelSize: root.popup_st.fs(-2)
        }

        Loader {
            active: !root.is_advanced && root.popup_st.console_views === "snes"
            visible: active
            Layout.preferredWidth: Style.px(36)
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: Snes.SnesGauge {
                implicitHeight: 7
                value: root.modelData.signalStrength || 0
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.activated()
    }
}
