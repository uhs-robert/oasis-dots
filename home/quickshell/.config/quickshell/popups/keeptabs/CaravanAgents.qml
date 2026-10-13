// home/quickshell/.config/quickshell/popups/keeptabs/CaravanAgents.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../../components"
import "../../components/oasis" as Oasis
import "../../theme"
import "KeeptabsFormat.js" as Fmt

// The Agents tab as caravan cards: one oasis card per session, a sky glyph for its state and the context
// as a horizon meter with a sun at the level. The contract is AgentsView's.
Item {
    id: root

    property var sessions: []
    property int selected: 0
    property int pick_exit: 0
    property var st: Style
    property var on_select: function (i) {}
    property var on_activate: function (id) {}
    property bool draws_footer: false

    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_primary, text_dim: root.st.text_dim })

    function ensure_visible(i) {
        session_list.positionViewAtIndex(i, ListView.Contain);
    }

    // Done is a sparkle, running a crescent, waiting a sand sun and idle a dim star, all drawn in a 12-unit box.
    component SkyGlyph: Shape {
        id: glyph

        property string mood: "idle"
        property color sand: "transparent"
        property color tone: "transparent"
        readonly property bool waiting: glyph.mood === "waiting"

        // Shape overwrites its own implicit size with its paths' bounds, so scaling from it (or from width) feeds back into itself.
        readonly property real glyph_size: 14

        Layout.preferredWidth: glyph.glyph_size
        Layout.preferredHeight: glyph.glyph_size
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: Qt.alpha(glyph.sand, 0.2)
            scale: Qt.size(glyph.glyph_size / 12, glyph.glyph_size / 12)
            PathSvg { path: glyph.waiting ? "M0 6a6 6 0 1 0 12 0a6 6 0 1 0 -12 0" : "M0 0" }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: glyph.mood === "waiting" ? glyph.sand : glyph.tone
            scale: Qt.size(glyph.glyph_size / 12, glyph.glyph_size / 12)
            PathSvg {
                path: glyph.mood === "done" ? "M6 0Q7.08 4.92 12 6Q7.08 7.08 6 12Q4.92 7.08 0 6Q4.92 4.92 6 0Z"
                    : glyph.mood === "running" ? "M9.5 0.8A6 6 0 1 0 9.5 11.2A5.2 5.2 0 0 1 9.5 0.8Z"
                    : glyph.waiting ? "M3 6a3 3 0 1 0 6 0a3 3 0 1 0 -6 0"
                    : "M4.8 6a1.2 1.2 0 1 0 2.4 0a1.2 1.2 0 1 0 -2.4 0"
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.sessions.length === 0
        text: root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed"
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    ListView {
        id: session_list
        anchors.fill: parent
        visible: root.sessions.length > 0
        clip: true
        spacing: 4
        model: root.sessions
        currentIndex: root.selected

        delegate: Oasis.OasisCard {
            id: card
            required property var modelData
            required property int index
            readonly property bool has_context: card.modelData.context_pct !== null && card.modelData.context_pct !== undefined
            readonly property real level: card.has_context ? Math.max(0, Math.min(100, card.modelData.context_pct)) / 100 : 0
            readonly property bool hot: card.level >= 0.85

            width: session_list.width
            height: Style.px(54)
            selected: card.index === root.selected
            critical: card.modelData.state === "waiting"

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    SkyGlyph {
                        mood: card.modelData.state || "idle"
                        sand: card.sand
                        tone: card.modelData.state === "done" ? card.sand : card.modelData.state === "running" ? root.st.text_primary : root.st.text_dim
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: card.modelData.title || "Untitled"
                        color: root.st.text_strong
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-1)
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: card.modelData.state || "idle"
                        color: Fmt.state_color(card.modelData.state, root.colors)
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: (card.modelData.agent || "claude") + " · " + (card.modelData.project || "") + " · " + (card.modelData.where || "") + " · " + Fmt.age(card.modelData.since)
                    color: root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-3)
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: card.has_context
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredHeight: 12

                        Meter {
                            id: meter
                            width: parent.width
                            anchors.verticalCenter: parent.verticalCenter
                            implicitHeight: 5
                            segment_count: 24
                            hot_from: 0.85
                            value: card.level
                        }

                        Rectangle {
                            readonly property real lit: Math.round(card.level * meter.segment_count)
                            readonly property real at: lit > 0 ? lit * (meter.segment_width + meter.gap) - meter.gap : 0
                            x: at - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            radius: 6
                            color: Qt.alpha(card.hot ? root.st.meter_hot : card.sand, 0.2)

                            Rectangle {
                                anchors.centerIn: parent
                                width: 7
                                height: 7
                                radius: 3.5
                                color: card.hot ? root.st.meter_hot : card.sand
                            }
                        }
                    }

                    Text {
                        text: card.has_context ? card.modelData.context_pct + "% · " + Fmt.fmt_tokens(card.modelData.context_used) + "/" + Fmt.fmt_tokens(card.modelData.context_window) : ""
                        color: root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.on_select(card.index);
                    root.on_activate(card.modelData.id);
                }
            }
        }
    }
}
