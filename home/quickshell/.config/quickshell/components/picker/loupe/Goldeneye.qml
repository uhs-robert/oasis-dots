// home/quickshell/.config/quickshell/components/picker/loupe/Goldeneye.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import "../../../theme"
import "../../../services"
import ".."
import "../../goldeneye" as Goldeneye
import "../../../theme/Watch.js" as Watch

Item {
    id: root

    required property var loupe
    readonly property real gap: 36
    readonly property real flip_gap: root.loupe.gap
    readonly property bool own_readout: false
    implicitWidth: root.ge_rim
    implicitHeight: root.ge_rim + root.ge_strip_gap + root.ge_strip_h

    readonly property real ge_rim: root.loupe.lens + 32
    readonly property real ge_strip_gap: 8
    readonly property real ge_strip_h: 52

    MultiEffect {
        anchors.fill: ge_rim_item
        source: ge_rim_item
        shadowEnabled: true
        shadowColor: Qt.alpha(Theme.bg_shadow, 0.6)
        shadowHorizontalOffset: 4
        shadowVerticalOffset: 6
        shadowBlur: 0.4
    }

    Item {
        id: ge_rim_item
        layer.enabled: true
        x: 0
        y: 0
        width: root.ge_rim
        height: root.ge_rim

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.bg_crust
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 10
            height: parent.height - 10
            radius: width / 2
            color: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.bg_crust, 0.5))
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 14
            height: parent.height - 14
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(Theme.fg_strong, 0.12)
        }

        Text {
            anchors.top: parent.top
            anchors.topMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            text: "x" + root.loupe.zoom + ".0"
            color: Theme.theme_label
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
        }
    }

    LoupeLens {
        id: lens
        loupe: root.loupe
        x: (root.ge_rim - root.loupe.view) / 2
        y: (root.ge_rim - root.loupe.view) / 2
        visible: false
        layer.enabled: true
        center_color: Theme.theme_label

        Canvas {
            id: ge_vignette
            anchors.fill: parent
            onPaint: {
                const ctx = ge_vignette.getContext("2d");
                ctx.clearRect(0, 0, ge_vignette.width, ge_vignette.height);
                const cx2 = ge_vignette.width / 2;
                const cy2 = ge_vignette.height / 2;
                const r = Math.max(cx2, cy2);
                const grad = ctx.createRadialGradient(cx2, cy2, r * 0.62, cx2, cy2, r);
                grad.addColorStop(0, Qt.alpha(Theme.bg_shadow, 0));
                grad.addColorStop(1, Qt.alpha(Theme.bg_shadow, 1));
                ctx.fillStyle = grad;
                ctx.fillRect(0, 0, ge_vignette.width, ge_vignette.height);
            }
            Component.onCompleted: ge_vignette.requestPaint()
        }

        Rectangle {
            x: 0
            y: lens.center_px.y + lens.center_px.height / 2
            width: Math.max(0, lens.center_px.x - 3)
            height: 1
            color: Theme.bg_shadow
        }

        Rectangle {
            x: lens.center_px.x + lens.center_px.width + 3
            y: lens.center_px.y + lens.center_px.height / 2
            width: Math.max(0, root.loupe.view - x)
            height: 1
            color: Theme.bg_shadow
        }

        Rectangle {
            x: lens.center_px.x + lens.center_px.width / 2
            y: 0
            width: 1
            height: Math.max(0, lens.center_px.y - 3)
            color: Theme.bg_shadow
        }

        Rectangle {
            x: lens.center_px.x + lens.center_px.width / 2
            y: lens.center_px.y + lens.center_px.height + 3
            width: 1
            height: Math.max(0, root.loupe.view - y)
            color: Theme.bg_shadow
        }

        Rectangle {
            x: 0
            y: (root.loupe.view - 30) / 2
            width: 3
            height: 30
            color: Theme.bg_shadow
        }

        Rectangle {
            x: root.loupe.view - 3
            y: (root.loupe.view - 30) / 2
            width: 3
            height: 30
            color: Theme.bg_shadow
        }

        Rectangle {
            x: (root.loupe.view - 30) / 2
            y: root.loupe.view - 3
            width: 30
            height: 3
            color: Theme.bg_shadow
        }
    }

    Rectangle {
        id: ge_lens_mask
        visible: false
        x: lens.x
        y: lens.y
        width: lens.width
        height: lens.height
        radius: width / 2
        layer.enabled: true
    }

    MultiEffect {
        x: lens.x
        y: lens.y
        width: lens.width
        height: lens.height
        source: lens
        maskEnabled: true
        maskSource: ge_lens_mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    Goldeneye.WatchReadout {
        id: ge_strip
        x: (root.ge_rim - root.loupe.view) / 2
        y: root.ge_rim + root.ge_strip_gap
        width: root.loupe.view
        height: root.ge_strip_h
        status: root.loupe.pixel_mode ? "COLOR" : "CAMERA"

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.alpha(Theme.bg_shadow, 0.6)
            shadowHorizontalOffset: 4
            shadowVerticalOffset: 6
            shadowBlur: 0.4
        }

        Rectangle {
            visible: root.loupe.pixel_mode
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 12
            height: 12
            border.width: 1
            border.color: Style.wk.dim
            color: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "transparent"
        }

        Text {
            visible: root.loupe.pixel_mode || !root.loupe.has_sel
            anchors.left: parent.left
            anchors.leftMargin: root.loupe.pixel_mode ? 26 : 10
            anchors.verticalCenter: parent.verticalCenter
            text: root.loupe.pixel_mode ? (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------") : "READY"
            color: Style.wk.lit
            font.family: root.loupe.pixel_mode ? Watch.digit_font : Watch.mono_font
            font.pixelSize: Style.fs(-3)
        }

        Goldeneye.SizeText {
            visible: !root.loupe.pixel_mode && root.loupe.has_sel
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width_px: Math.round(root.loupe.sel.width)
            height_px: Math.round(root.loupe.sel.height)
        }

        Column {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                text: "X " + root.loupe.pad4(root.loupe.screen_x + root.loupe.at.x)
                color: Qt.alpha(Style.wk.mid, 0.75)
                font.family: Watch.mono_font
                font.pixelSize: Style.fs(-7)
            }

            Text {
                text: "Y " + root.loupe.pad4(root.loupe.screen_y + root.loupe.at.y)
                color: Qt.alpha(Style.wk.mid, 0.75)
                font.family: Watch.mono_font
                font.pixelSize: Style.fs(-7)
            }
        }
    }
}
