import QtQuick
import QtQuick.Layouts
import qs.core
import qs.theme
import qs.features.popups
import "KeeptabsFormat.js" as Fmt

// The Agents tab as a Resident Evil status screen: the selected session's heart monitor and condition on top, and
// the whole party below, one row per session with its own small trace. Contract as in AgentsView.
Item {
    id: root

    property var sessions: []
    property int selected: 0
    property int pick_exit: 0
    property var st: Style
    property var on_select: function (i) {}
    property var on_activate: function (id) {}
    property bool draws_footer: false

    readonly property var current: root.sessions[root.selected] || null
    readonly property bool has_context: root.current !== null && root.current.context_pct !== null && root.current.context_pct !== undefined
    // The traces scroll only while the popup shows this tab and the machine is on mains power, as the bar's other
    // loops do; on battery they stand still.
    readonly property bool animating: Popups.open_name === "keeptabs" && root.visible && PowerSource.on_ac
    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_fg, text_dim: root.st.text_dim })

    // keeptabs-hook writes only these four states. Any other one keeps its own name in grey with a flat line, so a
    // new state shows up as itself instead of as a guess.
    function condition(state) {
        const s = state || "idle";
        if (s === "waiting") return { word: "CAUTION", color: Style.pal.warning, beat: "waiting", ms: 1500 };
        if (s === "running") return { word: "FINE", color: Style.pal.ok, beat: "running", ms: 1000 };
        if (s === "done") return { word: "DONE", color: Style.pal.info, beat: "done", ms: 2400 };
        if (s === "idle") return { word: "IDLE", color: root.st.text_dim, beat: "idle", ms: 0 };
        return { word: s.toUpperCase(), color: root.st.text_dim, beat: "idle", ms: 0 };
    }

    function ensure_visible(i) {
        party_list.positionViewAtIndex(i, ListView.Contain);
    }

    // One heartbeat as (x, y) pairs across a beat's width, y from -1 (top) to 1 (bottom); traced from the mockup.
    readonly property var beats: ({
        running: [[0, 0], [0.3, 0], [0.36, -0.25], [0.42, 0.1], [0.48, -1], [0.54, 0.55], [0.6, 0], [1, 0]],
        waiting: [[0, 0], [0.25, 0], [0.3, -0.4], [0.36, 0.3], [0.42, -0.7], [0.5, 0.5], [0.56, 0], [1, 0]],
        done: [[0, 0], [0.35, 0], [0.4, -0.3], [0.45, 0], [1, 0]],
        idle: [[0, 0], [1, 0]]
    })

    // A trace of `beat_count` beats across its width. It scrolls by moving one wider, pre-drawn canvas a beat to the
    // left and starting over, so a frame costs a translation and never a repaint.
    component EcgTrace: Item {
        id: trace

        property string beat: "idle"
        property color line_color: "white"
        property real line_width: 2
        property int beat_count: 3
        property int beat_ms: 0
        property bool running: false
        readonly property real beat_w: trace.width / trace.beat_count

        clip: true

        Canvas {
            id: strip
            width: trace.width + trace.beat_w
            height: trace.height

            onWidthChanged: strip.requestPaint()
            onHeightChanged: strip.requestPaint()
            Connections {
                target: trace
                function onBeatChanged() { strip.requestPaint(); }
                function onLine_colorChanged() { strip.requestPaint(); }
            }

            onPaint: {
                const ctx = strip.getContext("2d");
                ctx.reset();
                const pts = root.beats[trace.beat] || root.beats.idle;
                const mid = strip.height / 2;
                const amp = mid - trace.line_width;
                ctx.strokeStyle = trace.line_color;
                ctx.lineWidth = trace.line_width;
                ctx.lineJoin = "round";
                ctx.beginPath();
                for (let r = 0; r <= trace.beat_count; r++) {
                    for (const p of pts) {
                        const x = (r + p[0]) * trace.beat_w;
                        const y = mid + p[1] * amp;
                        if (r === 0 && p === pts[0]) ctx.moveTo(x, y);
                        else ctx.lineTo(x, y);
                    }
                }
                ctx.stroke();
            }

            NumberAnimation on x {
                running: trace.running && trace.beat_ms > 0
                from: 0
                to: -trace.beat_w
                duration: trace.beat_ms
                loops: Animation.Infinite
                onRunningChanged: if (!running) strip.x = 0
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        // --- Condition panel: the selected session ---
        Rectangle {
            id: panel
            readonly property var cond: root.condition(root.current ? root.current.state : "idle")

            Layout.fillWidth: true
            implicitHeight: panel_column.implicitHeight + 16
            radius: 6
            color: Qt.alpha(Theme.bg_shadow, 0.35)
            border.width: 2
            border.color: Style.frame_border_color

            ColumnLayout {
                id: panel_column
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        id: monitor
                        Layout.fillWidth: true
                        Layout.preferredHeight: Style.px(64)
                        color: Qt.alpha(Theme.bg_shadow, 0.8)
                        border.width: 1
                        border.color: Qt.alpha(panel.cond.color, 0.25)

                        Repeater {
                            model: 14

                            Rectangle {
                                required property int index
                                x: (index + 1) * monitor.width / 15
                                width: 1
                                height: monitor.height
                                color: Qt.alpha(panel.cond.color, 0.12)
                            }
                        }

                        Rectangle {
                            y: monitor.height / 2
                            width: monitor.width
                            height: 1
                            color: Qt.alpha(panel.cond.color, 0.12)
                        }

                        EcgTrace {
                            anchors.fill: parent
                            anchors.margins: 6
                            beat: panel.cond.beat
                            line_color: panel.cond.color
                            line_width: Style.px(2.5)
                            beat_ms: panel.cond.ms
                            running: root.animating && root.current !== null
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: false
                        Layout.preferredWidth: Style.px(118)
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0

                        Text {
                            text: "CONDITION"
                            color: Theme.theme_primary_light
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-5)
                            font.letterSpacing: 2
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.current ? panel.cond.word : "NO SIGNAL"
                            color: panel.cond.color
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(3)
                            font.bold: true
                            font.letterSpacing: 1
                            style: Text.Raised
                            styleColor: Style.text_shadow
                        }

                        Text {
                            visible: root.current !== null
                            text: root.current ? "for " + Fmt.age(root.current.since) : ""
                            color: root.st.text_muted
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: root.current ? (root.current.title || "Untitled") : root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed"
                        color: root.current ? Style.text_strong : root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-1)
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }

                    Text {
                        visible: root.current !== null
                        text: root.has_context ? root.current.context_pct + "%" : "--"
                        color: root.has_context ? Fmt.context_bar_color(root.current.context_pct, root.colors) : root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-1)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.current !== null
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: root.current ? [root.current.agent || "claude", root.current.project || "", root.current.where || ""].filter(x => x).join(" · ") : ""
                        color: root.st.text_muted
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }

                    Text {
                        visible: root.has_context
                        text: root.has_context ? Fmt.fmt_tokens(root.current.context_used) + " / " + Fmt.fmt_tokens(root.current.context_window) : ""
                        color: root.st.text_muted
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }
                }
            }
        }

        // --- Party: every session ---
        Text {
            Layout.topMargin: 2
            visible: root.sessions.length > 0
            text: "PARTY"
            color: Theme.theme_primary_light
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-5)
            font.letterSpacing: 3
        }

        ListView {
            id: party_list
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.sessions.length > 0
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: root.sessions
            currentIndex: root.selected

            delegate: Rectangle {
                id: member
                required property var modelData
                required property int index
                readonly property bool is_selected: member.index === root.selected
                readonly property var cond: root.condition(member.modelData.state)

                width: party_list.width
                height: Style.px(40)
                radius: 4
                color: member.is_selected ? Qt.alpha(member.cond.color, 0.12) : Qt.alpha(Theme.bg_shadow, 0.35)
                border.width: member.is_selected ? 2 : 1
                border.color: member.is_selected ? member.cond.color : Qt.alpha(Style.frame_border_color, 0.6)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: member.modelData.title || "Untitled"
                            color: member.is_selected ? Style.text_strong : root.st.text_fg
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: (member.modelData.project || "") + " · " + Fmt.age(member.modelData.since)
                            color: root.st.text_muted
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-5)
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: Style.px(84)
                        Layout.preferredHeight: Style.px(24)
                        color: Qt.alpha(Theme.bg_shadow, 0.8)

                        EcgTrace {
                            anchors.fill: parent
                            anchors.margins: 3
                            beat: member.cond.beat
                            line_color: member.cond.color
                            line_width: Style.px(1.5)
                            beat_ms: member.cond.ms
                            running: root.animating
                        }
                    }

                    Text {
                        Layout.preferredWidth: Style.px(58)
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        text: member.cond.word
                        color: member.cond.color
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                        font.bold: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.on_select(member.index);
                        root.on_activate(member.modelData.id);
                    }
                }
            }
        }

        // Keeps the panel at the top when the party list is hidden.
        Item {
            Layout.fillHeight: true
            visible: root.sessions.length === 0
        }
    }
}
