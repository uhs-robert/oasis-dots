// home/quickshell/.config/quickshell/lock/skins/Tie.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../../theme"
import "screensavers"

// A TIE cockpit targeting console: a trench-scope reticle hunts, locks green or loses red with the password.
Item {
    id: root

    property var ctx: null
    readonly property int unlock_ms: 900

    readonly property bool portrait: root.height > root.width
    readonly property real u: root.portrait ? Math.min(root.width / 58, root.height / 100) : Math.min(root.width, root.height * 16 / 9) / 100
    readonly property bool animate: !!root.ctx && root.ctx.animate
    readonly property string phase: root.ctx ? root.ctx.phase : "idle"

    readonly property color vec: root.phase === "wrong" ? Theme.red : root.phase === "unlock" ? Theme.green : (root.ctx ? root.ctx.tint_base : Theme.yellow)
    readonly property color hot: root.phase === "wrong" ? Theme.bright_red : root.phase === "unlock" ? Theme.bright_green : (root.ctx ? root.ctx.tint_bright : Theme.bright_yellow)
    readonly property color vec_dim: Qt.alpha(root.vec, 0.55)
    readonly property color vec_faint: Qt.alpha(root.vec, 0.3)
    readonly property string body_font: "B612 Mono"
    readonly property string head_font: "Oxanium"
    readonly property string mode_font: root.body_font
    readonly property color mode_color: root.hot

    function up(s) {
        return String(s || "").toUpperCase();
    }

    property bool blink_on: true

    Timer {
        interval: 500
        repeat: true
        running: root.animate
        onTriggered: root.blink_on = !root.blink_on
        onRunningChanged: root.blink_on = true
    }

    Connections {
        target: root.ctx
        function onRejected() {
            if (root.animate) shake.restart();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg_shadow

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: root.width / 2
                    centerY: root.height / 2
                    focalX: centerX
                    focalY: centerY
                    centerRadius: Math.max(root.width, root.height) * 0.75
                    focalRadius: 0
                    GradientStop { position: 0; color: Qt.tint(Theme.bg_crust, Qt.alpha(root.hot, 0.05)) }
                    GradientStop { position: 0.75; color: Theme.bg_shadow }
                }
                PathRectangle { width: root.width; height: root.height }
            }
        }

        // Static scanlines.
        Image {
            readonly property int period: Math.max(3, Math.round(root.u * 0.3))
            anchors.fill: parent
            fillMode: Image.Tile
            smooth: false
            source: "data:image/svg+xml;utf8," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='4' height='" + period + "'><rect width='4' height='1' fill='" + Theme.bg_shadow + "' fill-opacity='0.5'/></svg>")
        }
    }

    SequentialAnimation {
        id: shake
        loops: 3
        PropertyAction { target: shake_t; property: "x"; value: -root.u * 0.6 }
        PauseAnimation { duration: 60 }
        PropertyAction { target: shake_t; property: "x"; value: root.u * 0.6 }
        PauseAnimation { duration: 60 }
        PropertyAction { target: shake_t; property: "x"; value: 0 }
    }

    Component {
        id: crest_icon

        Item {
            id: crest
            property color crest_color: root.vec
            implicitWidth: root.u * 3.6
            implicitHeight: root.u * 3.6

            Repeater {
                model: 16
                Rectangle {
                    id: tooth
                    required property int index
                    width: crest.width * 0.1
                    height: crest.height * 0.12
                    x: (crest.width - width) / 2
                    y: crest.height * 0.04
                    color: crest.crest_color
                    transform: Rotation { angle: tooth.index * 22.5; origin.x: tooth.width / 2; origin.y: crest.height * 0.46 }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.76
                height: width
                radius: width / 2
                color: "transparent"
                border.width: Math.max(1, root.u * 0.09)
                border.color: crest.crest_color
            }

            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.6
                height: width
                radius: width / 2
                color: "transparent"
                border.width: Math.max(1, root.u * 0.09)
                border.color: crest.crest_color
            }

            Repeater {
                model: 8
                Rectangle {
                    id: spoke
                    required property int index
                    width: crest.width * 0.07
                    height: crest.height * 0.2
                    x: (crest.width - width) / 2
                    y: crest.height * 0.12
                    color: crest.crest_color
                    transform: Rotation { angle: spoke.index * 45 + 22.5; origin.x: spoke.width / 2; origin.y: crest.height * 0.38 }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.24
                height: width
                radius: width / 2
                color: crest.crest_color
            }
        }
    }

    Item {
        id: content
        anchors.fill: parent
        visible: root.phase !== "saver"
        transform: Translate { id: shake_t }

        RowLayout {
            id: top
            x: root.u * 3
            y: root.u * 2.4
            width: parent.width - x * 2
            spacing: root.u * 1.4

            Loader {
                Layout.alignment: Qt.AlignVCenter
                sourceComponent: crest_icon
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.u * 0.2

                Text {
                    text: "OASIS NETWORK"
                    color: root.vec
                    font.family: root.head_font
                    font.bold: true
                    font.pixelSize: root.u * 1.7
                    font.letterSpacing: root.u * 1.7 * 0.2
                }

                Text {
                    text: "SECURE TERMINAL // SECTOR 7-ALPHA"
                    color: root.vec_dim
                    font.family: root.body_font
                    font.pixelSize: root.u * 1
                    font.letterSpacing: root.u * 0.25
                }
            }

            Text {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                text: root.phase === "wrong" ? "ALERT STATUS: RED" : root.phase === "unlock" ? "ACCESS: GRANTED" : "ACCESS: RESTRICTED"
                color: root.vec_dim
                font.family: root.body_font
                font.pixelSize: root.u * 1
                font.letterSpacing: root.u * 0.2
            }
        }

        Rectangle {
            x: top.x
            y: top.y + top.height + root.u * 1
            width: top.width
            height: Math.max(1, root.u * 0.1)
            color: root.vec_faint
        }

        // Targeting scope: converging trench toward a vanishing point, with a hunting/locking/losing reticle.
        Item {
            id: scope
            x: top.x
            y: root.portrait ? term.y + term.height + root.u * 3.6 : top.y + top.height + root.u * 3.4
            width: root.portrait ? top.width : root.width * 0.42
            height: root.portrait ? Math.min(width * 1.2, strip.y - y - root.u * 2.6) : root.height - y - root.u * 8.5

            readonly property real vx: width * 0.5
            readonly property real vy: height * 0.42

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: root.vec
                    strokeWidth: Math.max(1, root.u * 0.12)
                    fillColor: "transparent"
                    PathRectangle { x: 1; y: 1; width: scope.width - 2; height: scope.height - 2 }
                }

                ShapePath {
                    strokeColor: root.vec_dim
                    strokeWidth: Math.max(1, root.u * 0.1)
                    fillColor: "transparent"
                    PathMove { x: scope.width * 0.065; y: 1 }
                    PathLine { x: scope.width * 0.065; y: scope.height - 1 }
                    PathMove { x: scope.width * 0.935; y: 1 }
                    PathLine { x: scope.width * 0.935; y: scope.height - 1 }
                }

                // Trench rails from the four corners to the vanishing point.
                ShapePath {
                    strokeColor: root.vec_dim
                    strokeWidth: Math.max(1, root.u * 0.1)
                    fillColor: "transparent"
                    PathMove { x: scope.width * 0.065; y: scope.height * 0.06 }
                    PathLine { x: scope.vx; y: scope.vy }
                    PathMove { x: scope.width * 0.065; y: scope.height * 0.96 }
                    PathLine { x: scope.vx; y: scope.vy }
                    PathMove { x: scope.width * 0.935; y: scope.height * 0.96 }
                    PathLine { x: scope.vx; y: scope.vy }
                    PathMove { x: scope.width * 0.935; y: scope.height * 0.06 }
                    PathLine { x: scope.vx; y: scope.vy }
                }

                ShapePath {
                    strokeColor: root.vec_faint
                    strokeWidth: Math.max(1, root.u * 0.08)
                    fillColor: "transparent"
                    PathMove { x: scope.width * 0.24; y: scope.height * 0.96 }
                    PathLine { x: scope.vx; y: scope.vy }
                    PathMove { x: scope.width * 0.41; y: scope.height * 0.96 }
                    PathLine { x: scope.vx; y: scope.vy }
                    PathMove { x: scope.width * 0.59; y: scope.height * 0.96 }
                    PathLine { x: scope.vx; y: scope.vy }
                    PathMove { x: scope.width * 0.76; y: scope.height * 0.96 }
                    PathLine { x: scope.vx; y: scope.vy }
                }
            }

            // Rungs collapse toward the vanishing point on a shared, phase-independent clock.
            property real rung_t: 0
            NumberAnimation on rung_t {
                running: root.animate
                loops: Animation.Infinite
                from: 0
                to: 1
                duration: 3000
            }

            Repeater {
                model: 5
                Shape {
                    id: rung
                    required property int index
                    readonly property real t: (scope.rung_t + rung.index * 0.2) % 1
                    anchors.fill: parent
                    opacity: Math.min(1, rung.t * 6)
                    preferredRendererType: Shape.CurveRenderer
                    transform: Scale { origin.x: scope.vx; origin.y: scope.vy; xScale: Math.max(0.04, rung.t); yScale: Math.max(0.04, rung.t) }

                    ShapePath {
                        strokeColor: root.vec
                        strokeWidth: Math.max(1, root.u * 0.1)
                        fillColor: "transparent"
                        PathMove { x: scope.width * 0.065; y: scope.height * 0.06 }
                        PathLine { x: scope.width * 0.065; y: scope.height * 0.96 }
                        PathLine { x: scope.width * 0.935; y: scope.height * 0.96 }
                        PathLine { x: scope.width * 0.935; y: scope.height * 0.06 }
                    }
                }
            }

            // Crosshair at the vanishing point.
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: root.vec
                    strokeWidth: Math.max(1, root.u * 0.1)
                    fillColor: "transparent"
                    PathMove { x: scope.vx; y: scope.vy - scope.height * 0.08 }
                    PathLine { x: scope.vx; y: scope.vy - scope.height * 0.03 }
                    PathMove { x: scope.vx; y: scope.vy + scope.height * 0.03 }
                    PathLine { x: scope.vx; y: scope.vy + scope.height * 0.08 }
                    PathMove { x: scope.vx - scope.width * 0.08; y: scope.vy }
                    PathLine { x: scope.vx - scope.width * 0.03; y: scope.vy }
                    PathMove { x: scope.vx + scope.width * 0.03; y: scope.vy }
                    PathLine { x: scope.vx + scope.width * 0.08; y: scope.vy }
                }
            }

            // Drifting diamond target.
            Item {
                id: target
                x: scope.vx - width / 2
                y: scope.vy - height / 2
                width: root.u * 2
                height: width
                transform: Translate { id: target_t }

                SequentialAnimation {
                    running: root.animate
                    loops: Animation.Infinite
                    ParallelAnimation {
                        NumberAnimation { target: target_t; property: "x"; to: root.u * 1; duration: 2500; easing.type: Easing.InOutSine }
                        NumberAnimation { target: target_t; property: "y"; to: -root.u * 0.6; duration: 2500; easing.type: Easing.InOutSine }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: target_t; property: "x"; to: -root.u * 1; duration: 2500; easing.type: Easing.InOutSine }
                        NumberAnimation { target: target_t; property: "y"; to: root.u * 0.6; duration: 2500; easing.type: Easing.InOutSine }
                    }
                }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: root.hot
                        strokeWidth: Math.max(1, root.u * 0.14)
                        fillColor: "transparent"
                        PathMove { x: target.width * 0.5; y: 0 }
                        PathLine { x: target.width; y: target.height * 0.5 }
                        PathLine { x: target.width * 0.5; y: target.height }
                        PathLine { x: 0; y: target.height * 0.5 }
                        PathLine { x: target.width * 0.5; y: 0 }
                    }
                }
            }

            // Reticle brackets: hunt while idle/typing, snap in on unlock, thrash on wrong.
            Item {
                id: brk
                x: scope.vx - width / 2
                y: scope.vy - height / 2
                width: root.u * 9
                height: width
                transform: [
                    Scale { id: brk_scale; origin.x: brk.width / 2; origin.y: brk.height / 2 },
                    Translate { id: brk_t }
                ]

                SequentialAnimation {
                    running: root.animate && root.phase !== "wrong" && root.phase !== "unlock"
                    loops: Animation.Infinite
                    onStopped: { brk_t.x = 0; brk_t.y = 0; brk_scale.xScale = 1; brk_scale.yScale = 1; }
                    ParallelAnimation {
                        NumberAnimation { target: brk_t; property: "x"; to: root.u * 1.2; duration: 780; easing.type: Easing.InOutSine }
                        NumberAnimation { target: brk_t; property: "y"; to: -root.u * 0.7; duration: 780; easing.type: Easing.InOutSine }
                        NumberAnimation { target: brk_scale; property: "xScale"; to: 1.08; duration: 780; easing.type: Easing.InOutSine }
                        NumberAnimation { target: brk_scale; property: "yScale"; to: 1.08; duration: 780; easing.type: Easing.InOutSine }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: brk_t; property: "x"; to: -root.u * 0.9; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { target: brk_t; property: "y"; to: root.u * 0.5; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { target: brk_scale; property: "xScale"; to: 0.95; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { target: brk_scale; property: "yScale"; to: 0.95; duration: 900; easing.type: Easing.InOutSine }
                    }
                }

                SequentialAnimation {
                    running: root.animate && root.phase === "unlock"
                    loops: Animation.Infinite
                    PropertyAction { target: brk_scale; property: "xScale"; value: 1.5 }
                    PropertyAction { target: brk_scale; property: "yScale"; value: 1.5 }
                    ParallelAnimation {
                        NumberAnimation { target: brk_scale; property: "xScale"; to: 0.72; duration: 500; easing.type: Easing.OutCubic }
                        NumberAnimation { target: brk_scale; property: "yScale"; to: 0.72; duration: 500; easing.type: Easing.OutCubic }
                    }
                    PauseAnimation { duration: 900 }
                }

                SequentialAnimation {
                    running: root.animate && root.phase === "wrong"
                    loops: Animation.Infinite
                    ParallelAnimation {
                        NumberAnimation { target: brk_t; property: "x"; to: -root.u * 2.6; duration: 260; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: brk_t; property: "y"; to: root.u * 1.2; duration: 260; easing.type: Easing.InOutQuad }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: brk_t; property: "x"; to: root.u * 2.4; duration: 300; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: brk_t; property: "y"; to: -root.u * 1.4; duration: 300; easing.type: Easing.InOutQuad }
                    }
                }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: root.hot
                        strokeWidth: Math.max(1, root.u * 0.22)
                        fillColor: "transparent"
                        PathMove { x: brk.width * 0.32; y: brk.height * 0.32 }
                        PathLine { x: brk.width * 0.02; y: brk.height * 0.32 }
                        PathLine { x: brk.width * 0.02; y: brk.height * 0.02 }
                    }
                    ShapePath {
                        strokeColor: root.hot
                        strokeWidth: Math.max(1, root.u * 0.22)
                        fillColor: "transparent"
                        PathMove { x: brk.width * 0.68; y: brk.height * 0.32 }
                        PathLine { x: brk.width * 0.98; y: brk.height * 0.32 }
                        PathLine { x: brk.width * 0.98; y: brk.height * 0.02 }
                    }
                    ShapePath {
                        strokeColor: root.hot
                        strokeWidth: Math.max(1, root.u * 0.22)
                        fillColor: "transparent"
                        PathMove { x: brk.width * 0.32; y: brk.height * 0.68 }
                        PathLine { x: brk.width * 0.02; y: brk.height * 0.68 }
                        PathLine { x: brk.width * 0.02; y: brk.height * 0.98 }
                    }
                    ShapePath {
                        strokeColor: root.hot
                        strokeWidth: Math.max(1, root.u * 0.22)
                        fillColor: "transparent"
                        PathMove { x: brk.width * 0.68; y: brk.height * 0.68 }
                        PathLine { x: brk.width * 0.98; y: brk.height * 0.68 }
                        PathLine { x: brk.width * 0.98; y: brk.height * 0.98 }
                    }
                }
            }

            Text {
                x: root.u * 0.4
                y: -height - root.u * 0.4
                text: "TARGETING COMPUTER"
                color: root.vec
                font.family: root.body_font
                font.pixelSize: root.u * 0.85
                font.letterSpacing: root.u * 0.15
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: root.u * 0.4
                y: -height - root.u * 0.4
                text: "RANGE " + ({ idle: "0041.20", typing: "0027.85", wrong: "----.--", unlock: "0000.00" }[root.phase] || "0041.20")
                color: root.vec
                font.family: root.body_font
                font.pixelSize: root.u * 0.85
                font.letterSpacing: root.u * 0.15
            }

            Rectangle {
                anchors.fill: scope_status
                anchors.margins: -root.u * 0.5
                visible: scope_status.opacity > 0
                color: Theme.bg_shadow
            }

            Text {
                id: scope_status
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.u * 0.8
                opacity: root.phase !== "idle" || root.blink_on ? 1 : 0
                text: root.phase === "wrong" ? "NO LOCK" : root.phase === "unlock" ? "LOCK" : root.phase === "typing" ? "ACQUIRING" : "AWAITING CLEARANCE"
                color: root.vec
                font.family: root.head_font
                font.bold: root.phase === "wrong" || root.phase === "unlock"
                font.pixelSize: (root.phase === "wrong" || root.phase === "unlock") ? root.u * 1.5 : root.u * 1.05
                font.letterSpacing: root.u * 0.3
            }
        }

        // Terminal: clock, identity and the clearance gate.
        Item {
            id: term
            x: root.portrait ? top.x : root.width * 0.5
            y: top.y + top.height + root.u * 1.6
            width: root.width - x - root.u * 3
            height: gate.y + gate.height

            Text {
                text: "STANDARD TIME"
                color: root.vec_dim
                font.family: root.body_font
                font.pixelSize: root.u * 0.85
                font.letterSpacing: root.u * 0.2
            }

            Text {
                id: clock
                y: root.u * 1.4
                text: root.ctx ? root.ctx.time_text : ""
                color: root.hot
                font.family: root.head_font
                font.pixelSize: root.u * 6.2
                font.letterSpacing: root.u * 0.2
            }

            Text {
                id: date
                y: clock.y + clock.height + root.u * 0.2
                text: root.up(root.ctx ? root.ctx.date_text : "")
                color: root.vec
                font.family: root.body_font
                font.pixelSize: root.u * 1.3
                font.letterSpacing: root.u * 0.2
            }

            GridLayout {
                id: ids
                y: date.y + date.height + root.u * 1.6
                columns: 2
                columnSpacing: root.u * 1.4
                rowSpacing: root.u * 0.3

                Text { text: "OPERATOR"; color: root.vec_dim; font.family: root.body_font; font.pixelSize: root.u * 1.1; font.letterSpacing: root.u * 0.15 }
                Text { text: root.up(root.ctx ? root.ctx.user : ""); color: root.vec; font.family: root.body_font; font.pixelSize: root.u * 1.1; font.letterSpacing: root.u * 0.15 }
                Text { text: "NODE"; color: root.vec_dim; font.family: root.body_font; font.pixelSize: root.u * 1.1; font.letterSpacing: root.u * 0.15 }
                Text { text: root.up(root.ctx ? root.ctx.host : ""); color: root.vec; font.family: root.body_font; font.pixelSize: root.u * 1.1; font.letterSpacing: root.u * 0.15 }
            }

            // The clearance gate: corner brackets, a title, code cells and a status line.
            Item {
                id: gate
                y: ids.y + ids.height + root.u * 2.2
                width: parent.width
                height: gate_col.implicitHeight + root.u * 2.4

                Rectangle {
                    anchors.fill: parent
                    color: root.phase === "wrong" ? Qt.alpha(Theme.red, 0.08) : "transparent"
                    border.width: Math.max(1, root.u * 0.12)
                    border.color: root.vec_dim
                }

                Repeater {
                    model: 2
                    Shape {
                        id: corner
                        required property int index
                        readonly property real inset: Math.max(2, root.u * 0.22) / 2
                        readonly property real cx: index === 0 ? inset : gate.width - inset
                        readonly property real cy: index === 0 ? inset : gate.height - inset
                        readonly property real sx: index === 0 ? 1 : -1
                        readonly property real sy: index === 0 ? 1 : -1
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeColor: root.hot
                            strokeWidth: Math.max(2, root.u * 0.22)
                            fillColor: "transparent"
                            PathMove { x: corner.cx; y: corner.cy + corner.sy * root.u * 1.4 }
                            PathLine { x: corner.cx; y: corner.cy }
                            PathLine { x: corner.cx + corner.sx * root.u * 1.4; y: corner.cy }
                        }
                    }
                }

                ColumnLayout {
                    id: gate_col
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: root.u * 1.6
                    spacing: root.u * 0.8

                    Text {
                        opacity: root.phase === "idle" && !root.blink_on ? 0.2 : 1
                        text: root.phase === "wrong" ? "CODE REJECTED" : root.phase === "unlock" ? "CODE ACCEPTED" : "CLEARANCE CODE REQUIRED"
                        color: root.hot
                        font.family: root.head_font
                        font.bold: true
                        font.pixelSize: root.u * 1.6
                        font.letterSpacing: root.u * 0.3
                    }

                    RowLayout {
                        spacing: root.u * 0.5

                        Repeater {
                            model: 8
                            Rectangle {
                                id: cell
                                required property int index
                                readonly property int filled: root.phase === "unlock" ? 8 : Math.min(root.ctx ? root.ctx.buffer_length : 0, 8)
                                readonly property bool current: cell.index === cell.filled && root.phase !== "unlock"
                                implicitWidth: root.u * 2.6
                                implicitHeight: root.u * 3
                                color: "transparent"
                                border.width: Math.max(1, root.u * 0.12)
                                border.color: cell.current ? root.hot : root.vec_dim
                                opacity: cell.current && !root.blink_on ? 0.3 : 1

                                Rectangle {
                                    visible: cell.index < cell.filled
                                    anchors.fill: parent
                                    anchors.margins: root.u * 0.5
                                    color: root.hot
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: {
                            const c = root.ctx;
                            if (!c) return "";
                            if (root.phase === "wrong") return "ATTEMPT " + String(Math.max(1, c.fail_count)).padStart(2, "0") + " LOGGED // SECURITY NOTIFIED";
                            if (root.phase === "unlock") return "WELCOME ABOARD, OPERATOR " + root.up(c.user);
                            if (root.phase === "typing") return "CODE SEGMENTS RECEIVED: " + c.buffer_length;
                            return "PRESS ANY KEY TO BEGIN AUTHENTICATION";
                        }
                        color: root.vec_dim
                        font.family: root.body_font
                        font.pixelSize: root.u * 1
                        font.letterSpacing: root.u * 0.15
                    }
                }
            }
        }

        Rectangle {
            x: root.u * 3
            y: strip.y - root.u * 0.7
            width: parent.width - x * 2
            height: Math.max(1, root.u * 0.1)
            color: root.vec_faint
        }

        GridLayout {
            id: strip
            x: root.u * 3
            y: root.portrait ? parent.height - height - root.u * 1.8 : parent.height - root.u * 2.9
            width: parent.width - x * 2
            columns: root.portrait ? 3 : 5
            columnSpacing: 0
            rowSpacing: root.u * 0.6

            Repeater {
                model: {
                    const c = root.ctx;
                    if (!c) return [];
                    return [
                        ["PWR", c.has_battery ? c.battery_percent + "%" + (c.charging ? " CHG" : "") : "AC MAINS"],
                        ["ATMOS", c.has_weather ? root.up(c.weather_temp + " " + c.weather_cond) : "NO SIGNAL"],
                        ["TRANSMISSIONS", String(c.notifications).padStart(2, "0")],
                        ["NEXT", c.has_event ? root.up(c.event_time + " " + c.event_title) : "NONE SCHEDULED"],
                        ["AUDIO", c.has_media ? root.up(c.media_status) : "IDLE"]
                    ];
                }

                RowLayout {
                    id: stat
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: root.u * 0.6

                    Rectangle {
                        Layout.preferredWidth: Math.max(1, root.u * 0.1)
                        Layout.fillHeight: true
                        visible: stat.index % strip.columns > 0
                        color: root.vec_faint
                    }

                    Text {
                        text: stat.modelData[0]
                        color: root.vec_dim
                        font.family: root.body_font
                        font.pixelSize: root.u * 0.95
                        font.letterSpacing: root.u * 0.1
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: stat.modelData[1]
                        color: root.vec
                        font.family: root.body_font
                        font.pixelSize: root.u * 0.95
                        font.letterSpacing: root.u * 0.1
                    }
                }
            }
        }
    }

    // A brightening pulse across the console when the code is accepted.
    Rectangle {
        anchors.fill: parent
        visible: root.phase === "unlock"
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(root.hot, 0.22) }
            GradientStop { position: 0.5; color: "transparent" }
        }

        SequentialAnimation on opacity {
            running: root.animate && root.phase === "unlock"
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 720; easing.type: Easing.OutQuad }
            NumberAnimation { from: 1; to: 0; duration: 880; easing.type: Easing.InQuad }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.phase === "saver"
        sourceComponent: saver_view
    }

    Component {
        id: saver_view

        Item {
            id: saver

            Starfield {
                anchors.fill: parent
                running: root.animate
                color: root.hot
                dim_color: root.vec_dim
                count: 260
                render_scale: 0.5
            }

            Repeater {
                model: [saver_head, saver_time, saver_info, saver_strip]

                Rectangle {
                    required property var modelData
                    x: modelData.x - root.u * 1
                    y: modelData.y - root.u * 0.8
                    width: modelData.width + root.u * 2
                    height: modelData.height + root.u * 1.6
                    radius: root.u * 0.3
                    color: Qt.alpha(Theme.bg_shadow, 0.85)
                }
            }

            RowLayout {
                id: saver_head
                x: root.u * 3
                y: root.u * 3
                spacing: root.u * 1.2

                Loader { sourceComponent: crest_icon }

                ColumnLayout {
                    spacing: root.u * 0.2

                    Text {
                        text: "HYPERSPACE"
                        color: root.vec
                        font.family: root.head_font
                        font.bold: true
                        font.pixelSize: root.u * 1.5
                        font.letterSpacing: root.u * 0.3
                    }

                    Text {
                        text: "STANDBY // NODE " + root.up(root.ctx ? root.ctx.host : "")
                        color: root.vec_dim
                        font.family: root.body_font
                        font.pixelSize: root.u * 1
                        font.letterSpacing: root.u * 0.15
                    }
                }
            }

            ColumnLayout {
                id: saver_time
                anchors.right: parent.right
                anchors.rightMargin: root.u * 3
                y: root.u * 3
                spacing: root.u * 0.2

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: "STANDARD TIME"
                    color: root.vec_dim
                    font.family: root.body_font
                    font.pixelSize: root.u * 1
                    font.letterSpacing: root.u * 0.2
                }

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: root.ctx ? root.ctx.time_text : ""
                    color: root.hot
                    font.family: root.head_font
                    font.pixelSize: root.u * 4.4
                }

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: root.up(root.ctx ? root.ctx.date_text : "")
                    color: root.vec
                    font.family: root.body_font
                    font.pixelSize: root.u * 1.3
                }
            }

            Text {
                id: saver_info
                x: root.u * 3
                y: root.u * 10
                lineHeight: 1.4
                text: "GRID 7-ALPHA<br>CONTACTS " + String(root.ctx ? root.ctx.notifications : 0).padStart(2, "0") + "<br>OPERATOR " + root.up(root.ctx ? root.ctx.user : "")
                textFormat: Text.StyledText
                color: root.vec_dim
                font.family: root.body_font
                font.pixelSize: root.u * 1
                font.letterSpacing: root.u * 0.15
            }

            Rectangle {
                x: root.u * 3
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.u * 3.6
                width: parent.width - x * 2
                height: Math.max(1, root.u * 0.1)
                color: root.vec_faint
            }

            RowLayout {
                id: saver_strip
                x: root.u * 3
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.u * 1.6
                width: parent.width - x * 2
                spacing: root.u * 1.4

                Text {
                    readonly property var c: root.ctx
                    text: c ? (c.has_battery ? "PWR " + c.battery_percent + "%" + (c.charging ? " CHG" : "") : "PWR AC") : ""
                    color: root.vec_dim
                    font.family: root.body_font
                    font.pixelSize: root.u * 0.95
                }

                Text {
                    readonly property var c: root.ctx
                    visible: !!c && c.has_weather
                    text: c ? "ATMOS " + root.up(c.weather_temp + " " + c.weather_cond) : ""
                    color: root.vec_dim
                    font.family: root.body_font
                    font.pixelSize: root.u * 0.95
                }
            }
        }
    }
}
