// home/quickshell/.config/quickshell/lock/LockScreen.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import "../theme"
import "../services"

// One screen of the lock: a big clock and date, a frosted password line, then now playing and the weather.
Item {
    id: root

    // Handed in by the lock host (or the preview); all auth state is read from it.
    property var ctx: null
    // Set by the host to this surface's output, which picks its backdrop screenshot.
    property string screen_name: ""
    // The host holds the session this long after PAM succeeds, so the backdrop can sharpen back into the desktop.
    readonly property int unlock_ms: 600

    readonly property string backdrop_mode: root.ctx ? root.ctx.backdrop_mode : "off"
    readonly property string backdrop_source: root.ctx && root.backdrop_mode !== "off" ? root.ctx.backdrops[root.screen_name] || "" : ""
    readonly property bool has_backdrop: root.backdrop_source !== "" && shot.status === Image.Ready
    readonly property bool animate: root.ctx ? root.ctx.animate : Power.on_ac
    readonly property bool unlocking: !!root.ctx && root.ctx.phase === "unlock"

    // 0 shows the sharp capture, 1 the full pixelation or blur; the pixel size only changes at quarter marks.
    property real veil: 0
    property real content_opacity: 0
    property bool started: false
    readonly property var steps: [0, 480, 240, 120, 60]
    readonly property int blocks: root.steps[Math.min(4, Math.ceil(root.veil * 4))]

    readonly property int text_style: Style.glow ? Text.Outline : Style.text_shadow.a > 0 ? Text.Raised : Text.Normal
    readonly property color glow_color: Style.glow ? Qt.alpha(Theme.theme_primary, 0.3) : Style.text_shadow
    readonly property color clock_color: root.ctx ? root.ctx.tint_strong : Theme.theme_primary_strong
    readonly property string user_name: Quickshell.env("USER") || ""
    readonly property var player: MediaState.active
    readonly property bool has_media: !!root.player && (root.player.trackTitle || "") !== ""
    readonly property bool has_weather: WeatherState.has_data && !!WeatherState.current
    readonly property int buffer_length: root.ctx ? root.ctx.buffer_length : 0
    readonly property bool checking: !!root.ctx && root.ctx.checking
    readonly property bool failed: !!root.ctx && root.ctx.failed
    property bool caret_on: true

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    readonly property string time_text: {
        const d = clock.date;
        const m = d.getMinutes();
        return (d.getHours() % 12 || 12) + ":" + (m < 10 ? "0" + m : m);
    }

    function begin() {
        if (root.started) return;
        root.started = true;
        backdrop_wait.stop();
        if (!root.animate) {
            root.veil = 1;
            root.content_opacity = root.unlocking ? 0 : 1;
            return;
        }
        if (root.unlocking) {
            root.veil = 1;
            root.content_opacity = 1;
            outro.start();
        } else if (root.has_backdrop) {
            intro.start();
        } else {
            root.veil = 1;
            fade_in.start();
        }
    }

    onUnlockingChanged: {
        if (!root.unlocking || !root.started || outro.running) return;
        intro.stop();
        fade_in.stop();
        if (root.animate) outro.start();
        else root.content_opacity = 0;
    }

    Component.onCompleted: {
        if (root.backdrop_source !== "" && root.animate && shot.status === Image.Loading) backdrop_wait.start();
        else root.begin();
    }

    Connections {
        target: shot
        function onStatusChanged() {
            if (shot.status !== Image.Loading) root.begin();
        }
    }

    // A slow decode never holds the screen back for long.
    Timer {
        id: backdrop_wait
        interval: 300
        onTriggered: root.begin()
    }

    SequentialAnimation {
        id: intro
        NumberAnimation { target: root; property: "veil"; from: 0; to: 1; duration: 320; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "content_opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
    }

    NumberAnimation {
        id: fade_in
        target: root
        property: "content_opacity"
        to: 1
        duration: 220
        easing.type: Easing.OutCubic
    }

    ParallelAnimation {
        id: outro
        NumberAnimation { target: root; property: "content_opacity"; to: 0; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "veil"; to: 0; duration: 520; easing.type: Easing.OutQuad }
    }

    Timer {
        interval: 530
        repeat: true
        running: Style.caret_blink && !!root.ctx && root.ctx.typing && root.animate
        onTriggered: root.caret_on = !root.caret_on
        onRunningChanged: root.caret_on = true
    }

    Item {
        id: scene
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.bg_core }
                GradientStop { position: 1; color: Theme.bg_crust }
            }
        }

        // The capture at full size: the pixel and blur layers draw from it, and it shows itself only when sharp.
        Image {
            id: shot
            anchors.fill: parent
            visible: root.has_backdrop && (root.backdrop_mode === "pixelate" ? root.blocks === 0 : root.veil === 0)
            source: root.backdrop_source
            cache: false
            asynchronous: true
            fillMode: Image.Stretch
            mipmap: true
        }

        // Rendered into a texture `blocks` wide and stretched without smoothing.
        ShaderEffectSource {
            anchors.fill: parent
            visible: root.has_backdrop && root.backdrop_mode === "pixelate" && root.blocks > 0
            sourceItem: root.backdrop_mode === "pixelate" ? shot : null
            smooth: false
            textureSize: Qt.size(Math.max(1, root.blocks), Math.max(1, Math.round(root.blocks * root.height / Math.max(1, root.width))))
        }

        Loader {
            anchors.fill: parent
            active: root.has_backdrop && root.backdrop_mode === "blur"
            visible: root.veil > 0
            sourceComponent: MultiEffect {
                source: shot
                blurEnabled: true
                blur: root.veil
                blurMax: 64
                autoPaddingEnabled: false
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: root.has_backdrop
            opacity: root.veil
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(Theme.bg_core, 0.55) }
                GradientStop { position: 1; color: Qt.alpha(Theme.bg_crust, 0.72) }
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: root.has_backdrop ? root.veil : 1

            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: root.width / 2
                    centerY: root.height * 0.42
                    focalX: centerX
                    focalY: centerY
                    centerRadius: Math.max(root.width, root.height) * 0.55
                    focalRadius: 0
                    GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary, 0.12) }
                    GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary, 0) }
                }
                PathRectangle { width: root.width; height: root.height }
            }
        }
    }

    ColumnLayout {
        id: column
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Style.px(20)
        spacing: Style.px(8)
        opacity: root.content_opacity
        visible: root.content_opacity > 0

        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.px(10)

            Text {
                id: time_label
                text: root.time_text
                color: root.clock_color
                font.family: Style.number_font
                font.pixelSize: Math.round(Math.min(root.width * 0.13, root.height * 0.17))
                font.weight: Font.Thin
                style: root.text_style
                styleColor: root.glow_color
            }

            Text {
                anchors.baseline: time_label.baseline
                text: clock.date.getHours() < 12 ? "AM" : "PM"
                color: Qt.alpha(root.clock_color, 0.75)
                font.family: Style.font_family
                font.pixelSize: Style.fs(6)
                font.weight: Font.Light
                style: root.text_style
                styleColor: root.glow_color
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: -Style.px(6)
            text: Qt.formatDateTime(clock.date, "dddd, MMMM d")
            color: Style.text_strong
            font.family: Style.font_family
            font.pixelSize: Style.fs(5)
            font.weight: Font.Light
            font.capitalization: Style.label_caps ? Font.AllUppercase : Font.MixedCase
            font.letterSpacing: Style.label_caps ? Style.caps_tracking : Style.px(1)
            style: root.text_style
            styleColor: root.glow_color
        }

        Item {
            Layout.preferredHeight: Style.px(44)
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "\u{f0004}  " + root.user_name
            color: Style.text_dim
            font.family: Style.font_family
            font.pixelSize: Style.fs(-1)
            style: root.text_style
            styleColor: root.glow_color
        }

        // Frosted glass: the scene right behind the line, blurred and tinted, so it reads over any desktop.
        Item {
            id: well
            readonly property int dot: Style.px(9)
            readonly property int dot_gap: Style.px(6)
            readonly property int max_dots: Math.max(1, Math.floor((well.width - dots.x - Style.px(24)) / (well.dot + well.dot_gap)))
            readonly property real corner: Math.min(well.height / 2, Style.radius(12))

            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Style.px(340)
            Layout.preferredHeight: Style.px(46)

            transform: Translate {
                id: shake
            }

            ShaderEffectSource {
                id: glass_src
                anchors.fill: parent
                visible: false
                sourceItem: scene
                sourceRect: Qt.rect(column.x + well.x + shake.x, column.y + well.y, well.width, well.height)
            }

            Rectangle {
                id: glass_mask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                radius: well.corner
            }

            MultiEffect {
                anchors.fill: parent
                source: glass_src
                blurEnabled: true
                blur: 1
                blurMax: 32
                autoPaddingEnabled: false
                maskEnabled: true
                maskSource: glass_mask
            }

            Rectangle {
                anchors.fill: parent
                radius: well.corner
                color: Qt.alpha(Theme.bg_crust, root.has_backdrop ? 0.38 : 0.55)
                border.width: Math.max(1, Style.frame_border_width)
                border.color: root.failed ? Theme.error : root.buffer_length > 0 ? Style.caret_color : Qt.alpha(Theme.fg_core, 0.16)
            }

            Rectangle {
                x: well.corner / 2
                y: 1
                width: well.width - well.corner
                height: 1
                color: Qt.alpha(Theme.fg_strong, 0.08)
            }

            Text {
                id: prompt_mark
                x: Style.px(16)
                anchors.verticalCenter: parent.verticalCenter
                text: Style.row_cursor !== "" ? Style.row_cursor : "\u{f033e}"
                color: Style.row_cursor !== "" ? Style.caret_color : Style.text_dim
                font.family: Style.row_cursor !== "" ? Style.font_family : Theme.font_family
                font.pixelSize: Style.fs(0)
                font.bold: Style.row_cursor !== ""
            }

            Row {
                id: dots
                x: prompt_mark.x + prompt_mark.implicitWidth + Style.px(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: well.dot_gap

                Repeater {
                    model: Math.min(root.buffer_length, well.max_dots)

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: well.dot
                        height: well.dot
                        radius: Style.rounded ? well.dot / 2 : 0
                        color: Style.text_accent
                    }
                }

                Rectangle {
                    visible: !root.checking && root.caret_on
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.rounded ? 2 : well.dot
                    height: Style.rounded ? Style.px(18) : well.dot + 2
                    color: Style.caret_color
                }
            }

            Text {
                visible: root.buffer_length === 0
                x: dots.x + Style.px(14)
                anchors.verticalCenter: parent.verticalCenter
                width: well.width - x - Style.px(14)
                elide: Text.ElideRight
                text: root.checking ? "Checking" : root.ctx && root.ctx.prompt ? root.ctx.prompt : "Password"
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(0)
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: Style.px(420)
            visible: text !== ""
            text: root.ctx ? root.ctx.message + (root.failed && root.ctx.fail_count > 1 ? " (" + root.ctx.fail_count + ")" : "") : ""
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: root.failed ? Theme.error : Style.text_dim
            font.family: Style.font_family
            font.pixelSize: Style.fs(-1)
            style: root.text_style
            styleColor: root.glow_color
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: !!root.ctx && root.ctx.caps_lock
            text: "Caps Lock is on"
            color: Theme.warning
            font.family: Style.font_family
            font.pixelSize: Style.fs(-1)
        }

        Item {
            Layout.preferredHeight: Style.px(24)
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.width * 0.8
            spacing: Style.px(24)

            RowLayout {
                visible: root.has_media
                spacing: Style.px(6)

                Text {
                    text: MediaState.playing ? "\u{f040a}" : "\u{f03e4}"
                    color: Style.text_primary
                    font.family: Theme.font_family
                    font.pixelSize: Style.fs(0)
                }

                Text {
                    Layout.maximumWidth: Style.px(360)
                    text: root.has_media ? root.player.trackTitle + (root.player.trackArtist ? "  " + root.player.trackArtist : "") : ""
                    elide: Text.ElideRight
                    color: Style.text_fg
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-1)
                    style: root.text_style
                    styleColor: root.glow_color
                }
            }

            RowLayout {
                visible: root.has_weather
                spacing: Style.px(4)

                Image {
                    readonly property int size: Style.px(24)
                    Layout.preferredWidth: size
                    Layout.preferredHeight: size
                    sourceSize.width: size * 2
                    sourceSize.height: size * 2
                    source: root.has_weather ? WeatherState.icon_source(WeatherState.current.code, WeatherState.current.is_day) : ""
                    smooth: true
                    mipmap: true
                }

                Text {
                    text: root.has_weather ? Math.round(WeatherState.current.temp) + "°" + WeatherState.unit_symbol() : ""
                    color: root.has_weather ? WeatherState.temp_color(WeatherState.current.temp) : Style.text_dim
                    font.family: Style.number_font
                    font.pixelSize: Style.fs(0)
                    style: root.text_style
                    styleColor: root.glow_color
                }

                Text {
                    text: root.has_weather ? WeatherState.current.cond : ""
                    color: Style.text_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-1)
                }
            }
        }
    }

    SequentialAnimation {
        id: shake_anim
        NumberAnimation { target: shake; property: "x"; to: -Style.px(10); duration: 45 }
        NumberAnimation { target: shake; property: "x"; to: Style.px(10); duration: 70 }
        NumberAnimation { target: shake; property: "x"; to: -Style.px(6); duration: 60 }
        NumberAnimation { target: shake; property: "x"; to: 0; duration: 50 }
    }

    Connections {
        target: root.ctx
        function onRejected() {
            if (root.animate) shake_anim.restart();
        }
    }
}
