// home/quickshell/.config/quickshell/lock/LockScreen.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import "../theme"
import "../services"

// One screen of the lock: clock, date, the password card, then now playing and the weather.
Item {
    id: root

    // Handed in by the lock host; this generic screen reads Lock directly.
    property var ctx: null
    // Set by the host to this surface's output, which picks its backdrop screenshot.
    property string screen_name: ""
    readonly property string backdrop_mode: root.ctx ? root.ctx.backdrop_mode : "off"
    readonly property string backdrop_source: root.ctx && root.backdrop_mode !== "off" ? root.ctx.backdrops[root.screen_name] || "" : ""
    readonly property bool has_backdrop: root.backdrop_source !== "" && shot.status === Image.Ready

    readonly property int text_style: Style.glow ? Text.Outline : Style.text_shadow.a > 0 ? Text.Raised : Text.Normal
    readonly property color glow_color: Style.glow ? Qt.alpha(Theme.theme_primary, 0.3) : Style.text_shadow
    readonly property string user_name: Quickshell.env("USER") || ""
    readonly property var player: MediaState.active
    readonly property bool has_media: !!root.player && (root.player.trackTitle || "") !== ""
    readonly property bool has_weather: WeatherState.has_data && !!WeatherState.current
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

    opacity: 0
    Component.onCompleted: {
        if (Power.on_ac) fade_in.start();
        else root.opacity = 1;
    }

    NumberAnimation {
        id: fade_in
        target: root
        property: "opacity"
        to: 1
        duration: 220
        easing.type: Easing.OutCubic
    }

    Timer {
        interval: 530
        repeat: true
        running: Style.caret_blink && Lock.typing && Power.on_ac
        onTriggered: root.caret_on = !root.caret_on
        onRunningChanged: root.caret_on = true
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.bg_core }
            GradientStop { position: 1; color: Theme.bg_crust }
        }
    }

    // A tiny decode stretched without smoothing is the pixelation: about 60 blocks across.
    Image {
        id: shot
        anchors.fill: parent
        visible: root.has_backdrop && root.backdrop_mode === "pixelate"
        source: root.backdrop_source
        cache: false
        asynchronous: true
        fillMode: Image.Stretch
        smooth: root.backdrop_mode !== "pixelate"
        sourceSize.width: root.backdrop_mode === "pixelate" ? 60 : Math.max(1, Math.round(root.width / 8))
    }

    Loader {
        anchors.fill: parent
        active: root.has_backdrop && root.backdrop_mode === "blur"
        sourceComponent: MultiEffect {
            source: shot
            blurEnabled: true
            blur: 1
            blurMax: 48
            autoPaddingEnabled: false
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.has_backdrop
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Theme.bg_core, 0.55) }
            GradientStop { position: 1; color: Qt.alpha(Theme.bg_crust, 0.72) }
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

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

    ColumnLayout {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Style.px(24)
        spacing: Style.px(10)

        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.px(8)

            Text {
                id: time_label
                text: root.time_text
                color: Style.text_strong
                font.family: Style.number_font
                font.pixelSize: Style.px(96)
                font.bold: Style.number_font !== Style.font_family
                style: root.text_style
                styleColor: root.glow_color
            }

            Text {
                anchors.baseline: time_label.baseline
                text: clock.date.getHours() < 12 ? "AM" : "PM"
                color: Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(6)
                style: root.text_style
                styleColor: root.glow_color
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(clock.date, "dddd, MMMM d")
            color: Style.text_primary
            font.family: Style.font_family
            font.pixelSize: Style.fs(4)
            font.capitalization: Style.label_caps ? Font.AllUppercase : Font.MixedCase
            font.letterSpacing: Style.label_caps ? Style.caps_tracking : 0
            style: root.text_style
            styleColor: root.glow_color
        }

        Item {
            Layout.preferredHeight: Style.px(18)
        }

        LockCard {
            id: card
            Layout.alignment: Qt.AlignHCenter
            title: "LOCKED"

            transform: Translate {
                id: shake
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.px(10)

                Text {
                    text: "\u{f0004}"
                    color: Style.text_primary
                    font.family: Theme.font_family
                    font.pixelSize: Style.fs(4)
                }

                Text {
                    Layout.fillWidth: true
                    text: root.user_name
                    elide: Text.ElideRight
                    color: Style.text_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(2)
                    font.bold: true
                    style: root.text_style
                    styleColor: root.glow_color
                }
            }

            Rectangle {
                id: well
                readonly property int dot: Style.px(9)
                readonly property int dot_gap: Style.px(6)
                readonly property int max_dots: Math.max(1, Math.floor((well.width - dots.x - Style.px(24)) / (well.dot + well.dot_gap)))

                Layout.fillWidth: true
                Layout.preferredHeight: Style.px(40)
                radius: Style.radius(6)
                color: Qt.alpha(Theme.bg_crust, 0.6)
                border.width: Math.max(1, Style.frame_border_width)
                border.color: Lock.failed ? Theme.error : Lock.buffer !== "" ? Style.caret_color : Style.frame_border_color

                Text {
                    id: prompt_mark
                    visible: Style.row_cursor !== ""
                    x: Style.px(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: Style.row_cursor
                    color: Style.caret_color
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(0)
                    font.bold: true
                }

                Row {
                    id: dots
                    x: prompt_mark.visible ? prompt_mark.x + prompt_mark.implicitWidth + Style.px(8) : Style.px(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: well.dot_gap

                    Repeater {
                        model: Math.min(Lock.buffer.length, well.max_dots)

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: well.dot
                            height: well.dot
                            radius: Style.rounded ? well.dot / 2 : 0
                            color: Style.text_accent
                        }
                    }

                    Rectangle {
                        visible: !Lock.checking && root.caret_on
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.rounded ? 2 : well.dot
                        height: Style.rounded ? Style.px(18) : well.dot + 2
                        color: Style.caret_color
                    }
                }

                Text {
                    visible: Lock.buffer === ""
                    x: dots.x + Style.px(18)
                    anchors.verticalCenter: parent.verticalCenter
                    width: well.width - x - Style.px(10)
                    elide: Text.ElideRight
                    text: Lock.checking ? "Checking" : Lock.prompt !== "" ? Lock.prompt : "Password"
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(0)
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: Lock.message + (Lock.failed && Lock.fail_count > 1 ? " (" + Lock.fail_count + ")" : "")
                wrapMode: Text.Wrap
                color: Lock.failed ? Theme.error : Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
            }

            Text {
                Layout.fillWidth: true
                visible: Lock.caps_lock
                text: "Caps Lock is on"
                color: Theme.warning
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
            }

            Text {
                Layout.fillWidth: true
                text: "Enter unlock   Esc clear"
                horizontalAlignment: Text.AlignRight
                color: Style.footer_fg
                font.family: Style.font_family
                font.pixelSize: Style.footer_size > 0 ? Style.footer_size : Style.fs(-3)
                font.italic: Style.footer_italic
            }
        }

        Item {
            Layout.preferredHeight: Style.px(10)
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.width * 0.8
            spacing: Style.px(28)

            RowLayout {
                visible: root.has_media
                spacing: Style.px(8)

                Text {
                    text: MediaState.playing ? "\u{f040a}" : "\u{f03e4}"
                    color: Style.text_primary
                    font.family: Theme.font_family
                    font.pixelSize: Style.fs(2)
                }

                Text {
                    Layout.maximumWidth: Style.px(420)
                    text: root.has_media ? root.player.trackTitle + (root.player.trackArtist ? "  " + root.player.trackArtist : "") : ""
                    elide: Text.ElideRight
                    color: Style.text_fg
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(0)
                    style: root.text_style
                    styleColor: root.glow_color
                }
            }

            RowLayout {
                visible: root.has_weather
                spacing: Style.px(6)

                Image {
                    readonly property int size: Style.px(34)
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
                    font.pixelSize: Style.fs(2)
                    style: root.text_style
                    styleColor: root.glow_color
                }

                Text {
                    text: root.has_weather ? WeatherState.current.cond : ""
                    color: Style.text_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(0)
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
        target: Lock
        function onRejected() { if (Power.on_ac) shake_anim.restart(); }
    }
}
