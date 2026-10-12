// home/quickshell/.config/quickshell/popups/keeptabs/PartyMemberWindow.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../components/nes"
import "../../theme"
import "../weather" as Weather
import "../../components/nes/Slimes.js" as Slimes
import "KeeptabsFormat.js" as Fmt

// One session as a Dragon Quest party member: a slime for its agent in a window named by the title, with H (context
// left), M (context used) and L (time in this state) beneath. The border turns orange as context runs out.
Weather.DqWindow {
    id: root

    required property var session
    property bool is_selected: false
    // Flips on the popup's blink timer; waiting members hop with it.
    property bool beat: false
    property var st: Style

    readonly property bool has_context: root.session.context_pct !== null && root.session.context_pct !== undefined
    readonly property bool low: root.has_context && root.session.context_pct >= 85
    readonly property string state_name: root.session.state || "idle"
    readonly property bool codex: root.session.agent === "codex"
    readonly property color orange: Style.pal.bright_yellow
    readonly property int pixel: 3

    title: root.session.title || "Untitled"
    color: root.state_name === "running" ? Style.pal.bg_surface : Theme.bg_crust
    border.color: root.low ? root.orange : Theme.fg_strong

    function slime_colors(): var {
        const body = root.state_name === "idle" ? Style.pal.fg_muted : root.codex ? Style.pal.red : Style.pal.blue;
        const shine = root.state_name === "idle" ? Style.pal.fg_dim : root.codex ? Style.pal.bright_red : Style.pal.bright_blue;
        return [Style.pal.bg_crust, Style.pal.fg_strong, Style.pal.yellow, Style.pal.bright_yellow, body, shine, Style.pal.fg_dim, Style.pal.red];
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        anchors.topMargin: 10
        spacing: 2

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Slimes.SIZE * root.pixel
            Layout.preferredHeight: Slimes.SIZE * root.pixel + root.pixel

            PixelSprite {
                y: root.state_name === "waiting" && root.beat ? 0 : root.pixel
                pixel: root.pixel
                colors: root.slime_colors()
                rows: root.state_name === "done" ? Slimes.KING_SLIME : Slimes.SLIME
            }

            Text {
                visible: root.state_name === "idle"
                anchors.right: parent.right
                anchors.top: parent.top
                text: "z"
                color: Theme.fg_strong
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-5)
                font.bold: true
            }
        }

        Repeater {
            model: [
                { key: "H", value: root.has_context ? Fmt.fmt_tokens(Math.max(0, root.session.context_window - root.session.context_used)) : "--", hot: false },
                { key: "M", value: root.has_context ? root.session.context_pct + "%" : "--", hot: root.low },
                { key: "L", value: Fmt.age(root.session.since), hot: false }
            ]

            delegate: RowLayout {
                id: stat
                required property var modelData
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: stat.modelData.key
                    color: root.is_selected ? Theme.fg_strong : root.st.text_dim
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-5)
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    text: stat.modelData.value
                    color: stat.modelData.hot ? root.orange : root.is_selected ? Theme.fg_strong : root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-5)
                }
            }
        }
    }

    Text {
        visible: root.is_selected
        x: 7
        y: 6
        text: "▶"
        color: Theme.fg_strong
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-5)
    }
}
