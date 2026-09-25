// home/quickshell/.config/quickshell/components/metroid/DoorHatch.qml
import QtQuick
import "../../theme"

// A Metroid door hatch: a blue shield in a grey frame, retracted to its edge panels when open.
Item {
    id: root

    property bool open: false
    property bool lit: false
    property bool empty: false
    property int count: 0
    property real open_t: root.open ? 1 : 0

    readonly property real core: root.height - 8
    readonly property color blue: Theme.info
    readonly property color frame_color: root.lit ? Qt.tint(Theme.theme_primary_light, Qt.alpha(Theme.fg_dim, 0.3)) : Qt.tint(Theme.bg_surface, Qt.alpha(Theme.fg_dim, root.empty ? 0.55 : 0.75))
    readonly property color shield_hi: root.empty ? Qt.tint(Theme.bg_core, Qt.alpha(root.blue, 0.3)) : Qt.tint(Theme.fg_strong, Qt.alpha(root.blue, 0.55))
    readonly property color shield_mid: root.empty ? Qt.tint(Theme.bg_core, Qt.alpha(root.blue, 0.24)) : root.blue
    readonly property color shield_lo: root.empty ? Qt.tint(Theme.bg_crust, Qt.alpha(root.blue, 0.14)) : Qt.tint(Theme.bg_core, Qt.alpha(root.blue, 0.45))
    readonly property color hatch: Qt.alpha(Theme.fg_strong, root.empty ? 0.1 : 0.16)

    Behavior on open_t {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -1
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: root.lit ? Qt.alpha(Theme.theme_secondary, 0.35) : root.empty || root.open ? "transparent" : Qt.alpha(root.blue, 0.25)
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.bg_crust
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: height / 2
        color: root.frame_color
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: height / 2
        color: Theme.bg_crust
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: height / 2
        opacity: root.open_t
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.bg_crust }
            GradientStop { position: 0.5; color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.ui_visual_bg, 0.7)) }
            GradientStop { position: 1; color: Theme.bg_crust }
        }
    }

    Repeater {
        model: [0, 1]

        Item {
            id: edge
            required property int index
            x: edge.index ? root.width - 4 - width : 4
            y: 4
            width: Math.round(root.core / 4)
            height: root.core
            clip: true
            opacity: root.open_t
            visible: opacity > 0

            Rectangle {
                x: edge.index ? edge.width - width : 0
                width: root.width - 8
                height: root.core
                radius: height / 2
                color: "transparent"
                border.width: 3
                border.color: root.blue
            }
        }
    }

    Canvas {
        id: shield
        anchors.centerIn: parent
        width: root.core
        height: root.core
        opacity: 1 - root.open_t
        scale: 1 - 0.3 * root.open_t
        visible: opacity > 0

        onWidthChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        Connections {
            target: root
            function onShield_hiChanged() { shield.requestPaint(); }
            function onShield_midChanged() { shield.requestPaint(); }
            function onShield_loChanged() { shield.requestPaint(); }
            function onHatchChanged() { shield.requestPaint(); }
        }

        onPaint: {
            const ctx = getContext("2d");
            const w = width, h = height;
            ctx.reset();
            ctx.beginPath();
            ctx.ellipse(0, 0, w, h);
            ctx.clip();
            const g = ctx.createRadialGradient(w * 0.4, h * 0.35, 0, w * 0.4, h * 0.35, w * 0.88);
            g.addColorStop(0, String(root.shield_hi));
            g.addColorStop(0.08, String(root.shield_hi));
            g.addColorStop(0.3, String(root.shield_mid));
            g.addColorStop(0.72, String(root.shield_lo));
            g.addColorStop(1, String(root.shield_lo));
            ctx.fillStyle = g;
            ctx.fillRect(0, 0, w, h);
            ctx.fillStyle = String(root.hatch);
            for (const a of [Math.PI / 6, -Math.PI / 6]) {
                ctx.save();
                ctx.translate(w / 2, h / 2);
                ctx.rotate(a);
                for (let x = -w; x <= w; x += 5)
                    ctx.fillRect(x, -h, 1, h * 2);
                ctx.restore();
            }
        }
    }

    Text {
        anchors.centerIn: parent
        opacity: 1 - root.open_t
        visible: opacity > 0 && !root.empty
        text: root.count
        color: Theme.fg_strong
        style: Text.Outline
        styleColor: Theme.bg_crust
        font.family: Style.number_font
        font.weight: Font.Bold
        font.pixelSize: Math.round(root.core / 2)
    }
}
