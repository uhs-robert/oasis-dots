// home/quickshell/.config/quickshell/lock/skins/Crt.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Io
import "../../theme"
import "screensavers"

// A green-phosphor terminal in a curved tube: powers on from a dot, collapses to a line and a dot on unlock.
Item {
    id: root

    property var ctx: null
    readonly property int unlock_ms: 1150

    readonly property bool portrait: root.height > root.width
    readonly property real u: root.portrait ? root.width / 64 : Math.min(root.width, root.height * 16 / 9) / 100
    // The phosphor: the lock tint's bright shade for text, its base for dim text, rings and the glass.
    readonly property color tint_base: root.ctx ? root.ctx.tint_base : Theme.green
    readonly property color ph: root.ctx ? root.ctx.tint_bright : Theme.bright_green
    readonly property color ph_dim: Qt.tint(Theme.bg_shadow, Qt.alpha(root.tint_base, 0.72))
    readonly property color ph_hot: Qt.tint(root.ph, Qt.alpha(Theme.fg_strong, 0.15))
    readonly property string font: "VT323"
    readonly property string mode_font: root.font
    readonly property color mode_color: root.ph
    readonly property bool animate: !!root.ctx && root.ctx.animate
    readonly property string phase: root.ctx ? root.ctx.phase : "idle"
    readonly property bool dimmed: root.phase === "wrong" || root.phase === "unlock"
    property bool blink_on: true

    function up(s) {
        return String(s || "").toUpperCase();
    }

    function dim_bright(dim, bright) {
        return "<font color='" + root.ph_dim + "'>" + dim + "</font>" + bright;
    }

    Component.onCompleted: {
        if (root.animate && root.phase === "idle") power_on.start();
    }

    onPhaseChanged: {
        if (root.phase === "unlock") {
            if (root.animate) power_off.start();
            return;
        }
        if (root.phase === "wrong") root.flash_denied();
        power_off.stop();
        tube.xScale = 1;
        tube.yScale = 1;
        scr.opacity = 1;
        flash.opacity = 0;
        dot.opacity = 0;
    }

    Connections {
        target: root.ctx
        function onRejected() {
            if (root.animate) jolt.restart();
            root.flash_denied();
        }
    }

    Timer {
        interval: 500
        repeat: true
        running: root.animate
        onTriggered: root.blink_on = !root.blink_on
        onRunningChanged: root.blink_on = true
    }

    // Skins are built per lock surface, so this is when the session locked.
    property var locked_at: new Date()

    function locked_for(now) {
        const mins = Math.floor((now - root.locked_at) / 60000);
        if (mins < 1) return "JUST NOW";
        const h = Math.floor(mins / 60);
        return (h > 0 ? h + "H " + String(mins % 60).padStart(2, "0") + "M" : mins + "M") + " AGO";
    }

    property real uptime_mins: NaN

    FileView {
        id: uptime_file
        path: "/proc/uptime"
        onLoaded: root.uptime_mins = Math.floor(parseFloat(uptime_file.text()) / 60)
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: uptime_file.reload()
    }

    function uptime_text() {
        const mins = root.uptime_mins;
        if (isNaN(mins)) return "UNKNOWN";
        const d = Math.floor(mins / 1440);
        const h = Math.floor(mins % 1440 / 60);
        const pad = n => String(n).padStart(2, "0");
        return (d > 0 ? d + "D " + pad(h) + "H " : h > 0 ? h + "H " : "") + pad(mins % 60) + "M";
    }

    // ACCESS DENIED flashes three times per rejection, then clears.
    property bool denied_on: true
    property int denied_toggles: 0

    function flash_denied() {
        root.denied_on = true;
        root.denied_toggles = 0;
        if (root.animate) denied_blink.restart();
    }

    Timer {
        id: denied_blink
        interval: 500
        repeat: true
        onTriggered: {
            root.denied_on = !root.denied_on;
            if (++root.denied_toggles >= 5) stop();
        }
    }

    // Bezel.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.width / 2
                centerY: root.height * 0.4
                focalX: centerX
                focalY: centerY
                centerRadius: Math.max(root.width, root.height) * 0.75
                focalRadius: 0
                GradientStop { position: 0; color: Qt.tint(Theme.bg_shadow, Qt.alpha(Theme.bg_surface, 0.6)) }
                GradientStop { position: 1; color: Theme.bg_shadow }
            }
            PathRectangle { width: root.width; height: root.height }
        }
    }

    Item {
        id: glass
        anchors.fill: parent

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: glass.width / 2
                    centerY: glass.height / 2
                    focalX: centerX
                    focalY: centerY
                    centerRadius: Math.max(glass.width, glass.height) * 0.6
                    focalRadius: 0
                    GradientStop { position: 0; color: Qt.tint(Theme.bg_shadow, Qt.alpha(root.tint_base, 0.09)) }
                    GradientStop { position: 0.85; color: Theme.bg_shadow }
                }
                PathRectangle { width: glass.width; height: glass.height }
            }
        }

        Item {
            id: scr
            anchors.fill: parent
            transform: [
                Scale {
                    id: tube
                    origin.x: scr.width / 2
                    origin.y: scr.height / 2
                },
                Translate {
                    id: shake
                }
            ]

            Loader {
                anchors.fill: parent
                sourceComponent: MultiEffect {
                    source: content
                    blurEnabled: true
                    blur: 0.45
                    blurMax: 32
                    brightness: 0.1
                    opacity: 0.65
                }
            }

            Item {
                id: content
                anchors.fill: parent

                Item {
                    id: main
                    anchors.fill: parent
                    visible: root.phase !== "saver"
                    opacity: root.dimmed ? 0.16 : 1

                    GridLayout {
                        id: hdr
                        x: root.u * 3.4
                        y: root.u * 2.6
                        width: parent.width - x * 2
                        columns: root.portrait ? 1 : 2

                        Text {
                            Layout.fillWidth: true
                            text: root.dim_bright("OASIS 0.0.0 · TERMINAL ",root.up(root.ctx ? root.ctx.host : ""))
                            textFormat: Text.StyledText
                            elide: Text.ElideRight
                            color: root.ph
                            font.family: root.font
                            font.pixelSize: root.u * 1.9
                        }

                        Text {
                            text: root.dim_bright(root.up(root.ctx ? root.ctx.date_text : "") + " · ", root.ctx ? root.ctx.time_text : "")
                            textFormat: Text.StyledText
                            color: root.ph
                            font.family: root.font
                            font.pixelSize: root.u * 1.9
                        }
                    }

                    Rectangle {
                        x: hdr.x
                        y: hdr.y + hdr.height + root.u * 0.3
                        width: hdr.width
                        height: Math.max(1, root.u * 0.18)
                        color: root.ph_dim
                    }

                    Rectangle {
                        id: title_box
                        anchors.horizontalCenter: parent.horizontalCenter
                        readonly property real base_y: hdr.y + hdr.height + root.u * 0.5 + root.u * 2.4
                        // Portrait sits the title and stats a little above the middle of the free space.
                        y: root.portrait ? Math.max(base_y, base_y + (prompt.y - base_y - (height + root.u * 3.8 + sub.height + stats.height)) * 0.4) : base_y
                        width: title.implicitWidth + root.u * 6
                        height: title.implicitHeight + root.u * 0.8
                        color: "transparent"
                        border.width: Math.max(1, root.u * 0.1)
                        border.color: root.ph

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Math.max(2, root.u * 0.2)
                            color: Qt.alpha(root.ph, 0.05)
                            border.width: Math.max(1, root.u * 0.1)
                            border.color: root.ph
                        }

                        Text {
                            id: title
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: font.letterSpacing / 2
                            readonly property real title_size: root.u * (root.portrait ? 9.5 : 7.6)
                            text: root.portrait ? "SYSTEM\nLOCKED" : "SYSTEM LOCKED"
                            horizontalAlignment: Text.AlignHCenter
                            color: root.ph
                            font.family: root.font
                            font.pixelSize: title_size
                            font.letterSpacing: title_size * 0.18
                        }
                    }

                    Text {
                        id: sub
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: title_box.y + title_box.height + root.u * 0.8
                        text: root.dim_bright("OPERATOR ", root.up(root.ctx ? root.ctx.user : "")) + "<font color='" + root.ph_dim + "'>" + (root.portrait ? "<br>" : " · ") + "AUTHORISATION REQUIRED</font>"
                        textFormat: Text.StyledText
                        horizontalAlignment: Text.AlignHCenter
                        color: root.ph
                        font.family: root.font
                        font.pixelSize: root.u * 1.8
                        font.letterSpacing: root.u * 1.8 * 0.12
                    }

                    GridLayout {
                        id: stats
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: sub.y + sub.height + root.u * 3
                        width: parent.width * (root.portrait ? 0.84 : 0.78)
                        columns: root.portrait ? 2 : 4
                        columnSpacing: root.u * 1.8
                        rowSpacing: root.u * 0.5

                        Repeater {
                            model: {
                                const c = root.ctx;
                                if (!c) return [];
                                const rows = [];
                                const bar = "#".repeat(Math.round(c.battery_percent / 10)).padEnd(10, ".");
                                rows.push(["POWER", c.has_battery ? c.battery_percent + "% [" + bar + "]" + (c.charging ? " CHG" : "") : "AC MAINS"]);
                                rows.push(["ATMOS", c.has_weather ? root.up(c.weather_temp + " " + c.weather_cond) : "NO SIGNAL"]);
                                rows.push(["MSGS", c.notifications + " PENDING · SEALED"]);
                                if (c.has_event) rows.push(["NEXT", root.up(c.event_time + " " + c.event_title)]);
                                rows.push(["AUDIO", c.has_media ? root.up(c.media_title) + " [" + root.up(c.media_status) + "]" : "IDLE"]);
                                rows.push(["SESSION", "LOCKED " + root.locked_for(c.now)]);
                                rows.push(["UPTIME", root.uptime_text()]);
                                const cells = [];
                                for (const r of rows) cells.push({ text: r[0], key: true }, { text: r[1], key: false });
                                return cells;
                            }

                            Text {
                                required property var modelData
                                Layout.fillWidth: !modelData.key
                                Layout.maximumWidth: modelData.key ? -1 : root.width * (root.portrait ? 0.6 : 0.3)
                                text: modelData.text
                                elide: Text.ElideRight
                                color: modelData.key ? root.ph_dim : root.ph
                                font.family: root.font
                                font.pixelSize: root.u * 2.1
                            }
                        }
                    }
                }

                Rectangle {
                    visible: root.phase === "wrong" || root.phase === "unlock"
                    anchors.centerIn: parent
                    width: banner.implicitWidth + root.u * 4.8
                    height: banner.implicitHeight + root.u * 0.8
                    opacity: root.phase === "wrong" && !root.denied_on ? 0 : 1
                    color: root.phase === "wrong" ? Theme.red : Qt.alpha(Theme.bg_shadow, 0.8)

                    Text {
                        id: banner
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: font.letterSpacing / 2
                        text: "ACCESS" + (root.portrait ? "\n" : " ") + (root.phase === "unlock" ? "GRANTED" : "DENIED")
                        horizontalAlignment: Text.AlignHCenter
                        color: root.phase === "wrong" ? Theme.bg_shadow : Theme.bright_green
                        font.family: root.font
                        font.pixelSize: root.u * 7
                        font.letterSpacing: root.u * 7 * 0.14
                    }
                }

                Text {
                    visible: root.phase === "wrong" || root.phase === "unlock"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * (root.portrait ? 0.72 : 0.64)
                    width: parent.width * 0.8
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: {
                        const c = root.ctx;
                        if (!c) return "";
                        if (root.phase === "unlock") return "WELCOME BACK, " + root.up(c.user);
                        return "ATTEMPT " + Math.max(1, c.fail_count) + (c.message !== "" ? " · " + root.up(c.message.replace(/\n/g, " · ")) : "");
                    }
                    color: root.ph
                    font.family: root.font
                    font.pixelSize: root.u * 2.2
                    font.letterSpacing: root.u * 2.2 * 0.14
                }

                Item {
                    id: prompt
                    visible: root.phase !== "saver"
                    x: root.u * 3.4
                    width: parent.width - x * 2
                    height: prompt_row.height + root.u * 0.6
                    y: parent.height - root.u * 2.6 - height

                    Rectangle {
                        width: parent.width
                        height: Math.max(1, root.u * 0.18)
                        color: root.ph_dim
                    }

                    GridLayout {
                        id: prompt_row
                        y: root.u * 0.6
                        width: parent.width
                        columns: 5
                        columnSpacing: root.u * 0.6
                        rowSpacing: root.u * 0.4

                        Text {
                            id: prompt_label
                            text: "> ENTER ACCESS CODE:"
                            color: root.ph_hot
                            font.family: root.font
                            font.pixelSize: root.u * 2.6
                        }

                        Text {
                            readonly property int shown: root.ctx ? (root.phase === "unlock" ? 8 : Math.min(root.ctx.buffer_length, root.portrait ? 10 : 32)) : 0
                            visible: shown > 0
                            text: "*".repeat(shown)
                            color: root.ph_hot
                            font.family: root.font
                            font.pixelSize: root.u * 2.6
                            font.letterSpacing: root.u * 2.6 * 0.3
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            visible: root.phase !== "unlock" && !(root.ctx && root.ctx.checking)
                            implicitWidth: root.u * 2.6 * 0.55
                            implicitHeight: root.u * 2.6 * 0.9
                            color: root.ph
                            opacity: root.blink_on ? 1 : 0
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        // Portrait drops the status under the prompt, where the row has no room for it.
                        Text {
                            Layout.row: root.portrait ? 1 : 0
                            Layout.column: root.portrait ? 0 : 4
                            Layout.columnSpan: root.portrait ? 5 : 1
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            text: {
                                const c = root.ctx;
                                if (!c) return "";
                                if (root.phase === "unlock") return "SESSION RESTORED";
                                if (c.caps_lock) return "CAPS LOCK ON";
                                if (c.checking) return "VERIFYING";
                                if (root.phase === "wrong") return "RETRY";
                                if (c.buffer_length > 0) return "RETURN TO SUBMIT";
                                return "PRESS ANY KEY";
                            }
                            color: {
                                const c = root.ctx;
                                if (!c || root.phase === "unlock") return root.ph_dim;
                                if (c.caps_lock) return Theme.warning;
                                return c.checking ? Theme.yellow : root.ph_dim;
                            }
                            font.family: root.font
                            font.pixelSize: root.u * 1.8
                        }
                    }
                }

                Loader {
                    anchors.fill: parent
                    active: root.phase === "saver"
                    sourceComponent: saver_view
                }
            }

            // The tube's brightness spike while it powers on or off.
            Rectangle {
                id: flash
                anchors.fill: parent
                color: Theme.fg_strong
                opacity: 0
            }
        }

        Rectangle {
            id: dot
            anchors.centerIn: parent
            width: root.u * 0.6
            height: width
            radius: width / 2
            color: Theme.fg_strong
            opacity: 0
        }

        Rectangle {
            id: roll
            visible: root.animate
            width: parent.width
            height: parent.height * 0.18
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.alpha(root.ph, 0.06) }
                GradientStop { position: 1; color: "transparent" }
            }

            NumberAnimation on y {
                running: root.animate
                loops: Animation.Infinite
                from: -glass.height * 0.2
                to: glass.height * 1.1
                duration: 7000
            }
        }

        // Static scanlines: a dark line every period.
        Image {
            readonly property int period: Math.max(3, Math.round(root.u * 0.27))
            readonly property int line: Math.max(1, Math.round(root.u * 0.09))
            anchors.fill: parent
            fillMode: Image.Tile
            smooth: false
            source: "data:image/svg+xml;utf8," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='4' height='" + period + "'><rect width='4' height='" + line + "' fill='" + Qt.rgba(Theme.bg_shadow.r, Theme.bg_shadow.g, Theme.bg_shadow.b, 1) + "' fill-opacity='0.55'/></svg>")
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: glass.width / 2
                    centerY: glass.height / 2
                    focalX: centerX
                    focalY: centerY
                    centerRadius: Math.hypot(glass.width, glass.height) / 2
                    focalRadius: 0
                    GradientStop { position: 0.68; color: "transparent" }
                    GradientStop { position: 1; color: Qt.alpha(Theme.bg_shadow, 0.7) }
                }
                PathRectangle { width: glass.width; height: glass.height }
            }

            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 0
                    y1: 0
                    x2: glass.height * 0.36
                    y2: glass.height
                    GradientStop { position: 0; color: Qt.alpha(Theme.fg_strong, 0.06) }
                    GradientStop { position: 0.22; color: Qt.alpha(Theme.fg_strong, 0.06) }
                    GradientStop { position: 0.4; color: "transparent" }
                }
                PathRectangle { width: glass.width; height: glass.height }
            }
        }

    }

    SequentialAnimation {
        id: power_on
        PropertyAction { target: tube; property: "xScale"; value: 0.004 }
        PropertyAction { target: tube; property: "yScale"; value: 0.004 }
        PropertyAction { target: flash; property: "opacity"; value: 0.9 }
        PropertyAction { target: dot; property: "opacity"; value: 1 }
        PauseAnimation { duration: 120 }
        PropertyAction { target: dot; property: "opacity"; value: 0 }
        NumberAnimation { target: tube; property: "xScale"; to: 1; duration: 260; easing.type: Easing.OutCubic }
        ParallelAnimation {
            NumberAnimation { target: tube; property: "yScale"; to: 1; duration: 360; easing.type: Easing.OutCubic }
            NumberAnimation { target: flash; property: "opacity"; to: 0.25; duration: 360 }
        }
        NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 500; easing.type: Easing.OutQuad }
    }

    SequentialAnimation {
        id: power_off
        PauseAnimation { duration: 420 }
        ParallelAnimation {
            NumberAnimation { target: tube; property: "yScale"; to: 0.006; duration: 200; easing.type: Easing.InCubic }
            NumberAnimation { target: flash; property: "opacity"; to: 0.8; duration: 200 }
        }
        NumberAnimation { target: tube; property: "xScale"; to: 0.004; duration: 190; easing.type: Easing.InCubic }
        PropertyAction { target: scr; property: "opacity"; value: 0 }
        ParallelAnimation {
            NumberAnimation { target: dot; property: "opacity"; from: 1; to: 0; duration: 300 }
            NumberAnimation { target: dot; property: "scale"; from: 1.4; to: 0.2; duration: 300 }
        }
    }

    SequentialAnimation {
        id: jolt
        loops: 2
        PropertyAction { target: shake; property: "x"; value: root.u * 0.6 }
        PauseAnimation { duration: 350 }
        PropertyAction { target: shake; property: "x"; value: -root.u * 0.6 }
        PropertyAction { target: shake; property: "y"; value: root.u * 0.2 }
        PauseAnimation { duration: 350 }
        PropertyAction { target: shake; property: "x"; value: 0 }
        PropertyAction { target: shake; property: "y"; value: 0 }
    }

    SequentialAnimation {
        running: root.animate && root.phase !== "unlock"
        loops: Animation.Infinite
        onStopped: scr.opacity = 1
        PropertyAction { target: scr; property: "opacity"; value: 1 }
        PauseAnimation { duration: 1280 }
        PropertyAction { target: scr; property: "opacity"; value: 0.96 }
        PauseAnimation { duration: 640 }
        PropertyAction { target: scr; property: "opacity"; value: 0.99 }
        PauseAnimation { duration: 640 }
        PropertyAction { target: scr; property: "opacity"; value: 0.95 }
        PauseAnimation { duration: 640 }
    }

    Component {
        id: saver_view

        Item {
            id: saver

            MatrixRain {
                anchors.fill: parent
                running: root.animate
                color: Theme.theme_primary_strong
                trail_color: Theme.theme_primary_strong
                font_family: root.font
                glyph_size: root.u * 2.2
                characters: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%&*+=<>:;?!/|"
            }

            Rectangle {
                anchors.centerIn: parent
                width: rtime.implicitWidth + root.u * 2
                height: rtime.implicitHeight
                color: Qt.alpha(Theme.bg_shadow, 0.7)

                Text {
                    id: rtime
                    anchors.centerIn: parent
                    text: root.ctx ? root.ctx.time_text : ""
                    color: root.ph
                    font.family: root.font
                    font.pixelSize: root.u * 5.4
                }
            }

            Text {
                x: root.u * 3.4
                y: root.u * 2.6
                text: "SYSTEM LOCKED<br>STANDBY<br><font color='" + root.ph + "'>" + root.up(root.ctx ? root.ctx.host : "") + "</font>"
                textFormat: Text.StyledText
                color: root.ph_dim
                lineHeight: 1.25
                font.family: root.font
                font.pixelSize: root.u * 1.8
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: root.u * 3.4
                y: root.u * 2.6
                horizontalAlignment: Text.AlignRight
                text: root.up(root.ctx ? root.ctx.date_text : "") + "<br>" + root.dim_bright("OPERATOR ", "<font color='" + root.ph + "'>" + root.up(root.ctx ? root.ctx.user : "") + "</font>")
                textFormat: Text.StyledText
                color: root.ph_dim
                lineHeight: 1.25
                font.family: root.font
                font.pixelSize: root.u * 1.8
            }

            Text {
                x: root.u * 3.4
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.u * 2.6
                text: {
                    const c = root.ctx;
                    if (!c) return "";
                    const pwr = c.has_battery ? "PWR " + c.battery_percent + "%" + (c.charging ? " CHG" : "") : "PWR AC";
                    return pwr + (c.has_weather ? "<br>ATM " + root.up(c.weather_temp + " " + c.weather_cond) : "");
                }
                textFormat: Text.StyledText
                color: root.ph_dim
                lineHeight: 1.25
                font.family: root.font
                font.pixelSize: root.u * 1.8
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: root.u * 3.4
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.u * 2.6
                horizontalAlignment: Text.AlignRight
                text: {
                    const c = root.ctx;
                    if (!c) return "";
                    return "CONTACTS <font color='" + root.ph + "'>" + c.notifications + "</font>" + (c.has_event ? "<br>NEXT " + root.up(c.event_time + " " + c.event_title) : "");
                }
                textFormat: Text.StyledText
                color: root.ph_dim
                lineHeight: 1.25
                font.family: root.font
                font.pixelSize: root.u * 1.8
            }
        }
    }
}
