import QtQuick
import QtQuick.Layouts
import "../../components/ps2" as Ps2
import "../../theme"
import "../../services"

// The PS2 system screen for the sun and moon: soft light drifting through dark blue space around an orbit ring, the sun and moon as glowing spheres on it.
// The ring is a full day: sunrise at its left end, sunset at its right, the day arc above the horizon and the night arc below.
Item {
    id: root

    property int day_cursor: 0
    property int first_day: 0
    property int day_span: 5
    property var on_select: function (i) {}

    readonly property var day: WeatherState.days[Math.max(0, Math.min(WeatherState.days.length - 1, root.day_cursor))]
    readonly property bool is_today: root.day_cursor === 0

    readonly property var moon_times: root.day ? WeatherState.moon_times_for_date(root.day.date) : ({ rise: null, set: null })
    readonly property real moon_phase: root.day ? WeatherState.moon_phase_for_date(root.day.date) : 0
    readonly property string next_full: root.day ? WeatherState.next_full_moon_label(root.day.date) : ""

    // The location clock only moves on the minute.
    property int clock_tick: 0
    readonly property real rise_minutes: root.hm_minutes(root.day ? root.day.sunrise : "")
    readonly property real set_minutes: root.hm_minutes(root.day ? root.day.sunset : "")
    readonly property bool has_sun: root.rise_minutes >= 0 && root.set_minutes > root.rise_minutes
    readonly property real now_minutes: {
        root.clock_tick;
        const loc = WeatherState.location_now();
        return loc.getUTCHours() * 60 + loc.getUTCMinutes();
    }
    readonly property bool sun_up: root.is_today && root.has_sun && root.now_minutes >= root.rise_minutes && root.now_minutes <= root.set_minutes
    // Where the sun is along the day arc, 0 at sunrise to 1 at sunset; a day that is not live rests at noon.
    readonly property real sun_fraction: root.sun_up ? (root.now_minutes - root.rise_minutes) / (root.set_minutes - root.rise_minutes) : 0.5
    // Where the moon is along the night arc, 0 at sunset to 1 at sunrise; at midnight unless the night is live.
    readonly property real moon_fraction: {
        if (!root.is_today || !root.has_sun || root.sun_up) return 0.5;
        const night = 1440 - (root.set_minutes - root.rise_minutes);
        const since_set = root.now_minutes >= root.set_minutes ? root.now_minutes - root.set_minutes : root.now_minutes + 1440 - root.set_minutes;
        return Math.max(0, Math.min(1, since_set / night));
    }

    readonly property real moon_size: Math.max(34, Math.min(64, root.width / 7))

    function hm_minutes(hm) {
        if (!hm) return -1;
        const parts = hm.split(":");
        if (parts.length !== 2) return -1;
        return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
    }

    function day_length() {
        if (!root.has_sun) return "—";
        const mins = root.set_minutes - root.rise_minutes;
        return Math.floor(mins / 60) + "h " + (mins % 60) + "m";
    }

    Timer {
        interval: 60000
        running: root.is_today
        repeat: true
        onTriggered: root.clock_tick++
    }

    component Caption: Text {
        color: Theme.theme_primary_light
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.2
        elide: Text.ElideRight
    }

    component GlassPanel: Rectangle {
        radius: 8
        border.width: 1
        border.color: Qt.alpha(Theme.theme_primary_light, 0.22)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary_light, 0.14) }
            GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary_strong, 0.05) }
        }
    }

    component StatPanel: GlassPanel {
        property string caption: ""
        property string value: ""
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        implicitHeight: stat_column.implicitHeight + 14

        Column {
            id: stat_column
            anchors.verticalCenter: parent.verticalCenter
            x: 10
            width: parent.width - 20
            spacing: 0

            Caption { width: parent.width; text: parent.parent.caption }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: parent.parent.value || "—"
                color: Theme.fg_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(3)
                font.weight: Font.ExtraLight
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: WeatherState.days.slice(root.first_day, root.first_day + root.day_span)

                Rectangle {
                    id: tab
                    required property var modelData
                    required property int index
                    readonly property int day_index: root.first_day + tab.index
                    readonly property bool selected: tab.day_index === root.day_cursor

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: tab_text.implicitHeight + 12
                    radius: 7
                    border.width: 1
                    border.color: tab.selected ? Qt.alpha(Theme.theme_primary_light, 0.7) : Qt.alpha(Theme.theme_primary_light, 0.16)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary_light, tab.selected ? 0.4 : 0.1) }
                        GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary_strong, tab.selected ? 0.16 : 0.03) }
                    }

                    Rectangle {
                        visible: tab.selected
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -1
                        width: parent.width * 0.6
                        height: 2
                        radius: 1
                        color: Theme.theme_primary_light
                    }

                    Text {
                        id: tab_text
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 6)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: tab.modelData.weekday
                        color: tab.selected ? Theme.fg_strong : Theme.theme_primary_light
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                        font.weight: tab.selected ? Font.Medium : Font.Light
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(tab.day_index)
                    }
                }
            }
        }

        Item {
            id: sky
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 110
            clip: true

            // The ring: a full ellipse, its day half bright and its night half faint.
            readonly property real cx: sky.width / 2
            readonly property real cy: sky.height * 0.56
            readonly property real rx: Math.max(30, sky.width / 2 - 34)
            readonly property real ry: Math.max(20, Math.min(sky.cy - 22, sky.height - sky.cy - 22, sky.rx * 0.8))
            property real orbit_phase: 0
            readonly property bool animating: root.visible && Popups.open_name === "weather"

            NumberAnimation on orbit_phase {
                from: 0
                to: Math.PI * 2
                duration: 48000
                loops: Animation.Infinite
                running: sky.animating
            }

            Rectangle {
                anchors.fill: parent
                radius: 10
                border.width: 1
                border.color: Qt.alpha(Theme.theme_primary_light, 0.18)
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.alpha(Theme.bg_shadow, 0.95) }
                    GradientStop { position: 0.55; color: Qt.alpha(Theme.theme_primary_strong, 0.16) }
                    GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary, 0.24) }
                }
            }

            Ps2.Haze {
                anchors.fill: parent
                horizon: sky.cy / sky.height
                towers: 9
                strength: 0.35
            }

            Repeater {
                model: 16

                Item {
                    id: mote
                    required property int index
                    // Whole-number laps per loop keep the drift seamless.
                    readonly property int laps: mote.index % 3 === 0 ? -1 : mote.index % 3 === 1 ? 1 : 2
                    readonly property real spread: 0.45 + 0.7 * ((mote.index * 37) % 16) / 16
                    readonly property real angle: sky.orbit_phase * mote.laps + mote.index * 2.399
                    readonly property real dot: 1.5 + (mote.index % 4) * 0.7
                    x: sky.cx + sky.rx * mote.spread * Math.cos(mote.angle) * 1.1
                    y: sky.cy + sky.ry * mote.spread * Math.sin(mote.angle) * 1.25
                    opacity: 0.35 + 0.35 * Math.sin(sky.orbit_phase * 4 + mote.index)

                    Rectangle {
                        anchors.centerIn: parent
                        width: mote.dot * 4
                        height: width
                        radius: width / 2
                        color: Qt.alpha(Theme.theme_primary_light, 0.12)
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: mote.dot
                        height: width
                        radius: width / 2
                        color: Theme.fg_strong
                    }
                }
            }

            Canvas {
                id: ring
                anchors.fill: parent
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.save();
                    ctx.translate(sky.cx, sky.cy);
                    ctx.scale(1, sky.ry / sky.rx);
                    for (const pass of [{ w: 7, a: 0.1 }, { w: 1.2, a: 1 }]) {
                        ctx.lineWidth = pass.w;
                        ctx.strokeStyle = Qt.alpha(Theme.theme_primary_light, 0.75 * pass.a);
                        ctx.beginPath();
                        ctx.arc(0, 0, sky.rx, Math.PI, 2 * Math.PI, false);
                        ctx.stroke();
                        ctx.strokeStyle = Qt.alpha(Theme.theme_primary_light, 0.28 * pass.a);
                        ctx.beginPath();
                        ctx.arc(0, 0, sky.rx, 0, Math.PI, false);
                        ctx.stroke();
                    }
                    ctx.restore();

                    const horizon = ctx.createLinearGradient(0, 0, sky.width, 0);
                    horizon.addColorStop(0, Qt.alpha(Theme.theme_primary_light, 0));
                    horizon.addColorStop(0.5, Qt.alpha(Theme.theme_primary_light, 0.4));
                    horizon.addColorStop(1, Qt.alpha(Theme.theme_primary_light, 0));
                    ctx.fillStyle = horizon;
                    ctx.fillRect(0, sky.cy, sky.width, 1);
                }

                Connections {
                    target: sky
                    function onCyChanged() { ring.requestPaint(); }
                    function onRxChanged() { ring.requestPaint(); }
                    function onRyChanged() { ring.requestPaint(); }
                }
                Connections {
                    target: Style
                    function onPalChanged() { ring.requestPaint(); }
                }
            }

            Ps2.Sphere {
                x: sky.cx - sky.rx - width / 2
                y: sky.cy - width / 2
                width: 8
                lit: root.has_sun
                color: Style.pal.yellow
            }

            Ps2.Sphere {
                x: sky.cx + sky.rx - width / 2
                y: sky.cy - width / 2
                width: 8
                lit: root.has_sun
                color: Style.pal.warning
            }

            Item {
                id: sun
                readonly property real a: Math.PI * (1 - root.sun_fraction)
                x: sky.cx + sky.rx * Math.cos(sun.a) - width / 2
                y: sky.cy - sky.ry * Math.sin(sun.a) - height / 2
                width: 24
                height: 24
                opacity: root.sun_up || !root.is_today ? 1 : 0.4
                visible: root.has_sun

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 2.6
                    height: width
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.alpha(Style.pal.yellow, root.sun_up ? 0.3 : 0.1) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }

                Ps2.Sphere {
                    anchors.fill: parent
                    lit: true
                    color: Style.pal.yellow
                }
            }

            Item {
                id: moon
                readonly property real a: Math.PI * root.moon_fraction
                x: sky.cx + sky.rx * Math.cos(moon.a) - width / 2
                y: sky.cy + sky.ry * Math.sin(moon.a) - height / 2
                width: Math.min(30, root.moon_size * 0.6)
                height: width

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 2.4
                    height: width
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary_light, 0.16) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }

                Image {
                    anchors.fill: parent
                    source: WeatherState.moon_icon_source(root.moon_phase)
                    sourceSize.width: 96
                    sourceSize.height: 96
                    smooth: true
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: sky.cy - height - 8
                spacing: 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.day_length()
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Math.round(Style.font_size * 1.8)
                    font.weight: Font.ExtraLight
                }

                Caption {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Day length · " + (root.day ? Qt.formatDate(new Date(root.day.date + "T00:00:00"), "ddd d MMM") : "")
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            StatPanel {
                caption: "Sunrise"
                value: root.day ? WeatherState.fmt_hm(root.day.sunrise) : ""
            }

            StatPanel {
                caption: "Sunset"
                value: root.day ? WeatherState.fmt_hm(root.day.sunset) : ""
            }
        }

        GlassPanel {
            Layout.fillWidth: true
            implicitHeight: Math.max(moon_texts.implicitHeight, root.moon_size) + 14

            Image {
                id: moon_icon
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: root.moon_size
                height: width
                source: WeatherState.moon_icon_source(root.moon_phase)
                sourceSize.width: 128
                sourceSize.height: 128
            }

            ColumnLayout {
                id: moon_texts
                anchors.left: moon_icon.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: WeatherState.moon_name(root.moon_phase)
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(2)
                    font.weight: Font.Light
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: "Moonrise " + (root.moon_times.rise || "—") + (root.moon_times.set ? "  ·  Moonset " + root.moon_times.set : "")
                    color: Theme.theme_primary_light
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: "Full moon " + root.next_full
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                }
            }
        }
    }
}
