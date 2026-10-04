// home/quickshell/.config/quickshell/components/picker/targets/Scopeitem.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../../../theme"
import "../../../services"
import "../.."
import ".."

// PS2 scope item dressing for the window/screen/region target: corner brackets, global X/Y
// rulers and CAMERA/class/size glass chips on the pick, blue outlines on the rest.
Item {
    id: root

    required property string screen_name
    required property rect sel
    required property bool mine
    required property bool target_mode
    required property point origin

    readonly property bool full: Screenshot.mode === "screen"
    readonly property bool region: Screenshot.mode === "region"
    readonly property string cls: root.region ? "AREA" : root.full ? root.screen_name : (Screenshot.targets[Screenshot.target_index] ? Screenshot.targets[Screenshot.target_index].label : "")
    readonly property real tx: root.sel.x
    readonly property real ty: root.sel.y
    readonly property real tw: root.sel.width
    readonly property real th: root.sel.height
    readonly property int inset: root.full ? 8 : 0
    readonly property real fx: root.tx + root.inset
    readonly property real fy: root.ty + root.inset
    readonly property real fw: root.tw - root.inset * 2
    readonly property real fh: root.th - root.inset * 2
    readonly property real cx: root.fx + root.fw / 2
    readonly property real cy: root.fy + root.fh / 2

    function pad4(v) {
        const n = Math.round(v);
        return (n < 0 ? "-" : "") + String(Math.abs(n)).padStart(4, "0");
    }

    Repeater {
        model: root.target_mode ? Screenshot.targets : []

        Item {
            id: other
            required property var modelData
            required property int index
            visible: other.modelData.screen === root.screen_name && other.index !== Screenshot.target_index && Screenshot.phase === "select"
            x: other.modelData.rect.x
            y: other.modelData.rect.y
            width: other.modelData.rect.width
            height: other.modelData.rect.height

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(Theme.blue, 0.3)
            }

            LabelPlate {
                target: other_label
            }

            Text {
                id: other_label
                x: 6
                y: 4
                text: other.modelData.label
                color: Qt.alpha(Theme.blue, 0.6)
                font.family: Style.font_family
                font.letterSpacing: 1
                font.pixelSize: Style.fs(-7)
            }
        }
    }

    Item {
        id: target_visuals
        visible: root.mine
        anchors.fill: parent

        Rectangle {
            x: root.fx
            y: root.fy
            width: root.fw
            height: root.fh
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(Theme.blue, 0.45)
        }

        CornerBrackets {
            x: root.fx
            y: root.fy
            width: root.fw
            height: root.fh
            color: Theme.blue
            inset: -3
            arm: 22
            thickness: 2
            all_corners: true
        }

        Rectangle {
            x: root.cx - 2
            y: root.cy - 2
            width: 5
            height: 5
            color: Qt.alpha(Theme.bg_shadow, 0.7)
        }

        Rectangle {
            x: root.cx - 1
            y: root.cy - 1
            width: 3
            height: 3
            color: Theme.fg_strong
        }

        Item {
            id: h_ruler
            visible: root.fw > 160
            x: root.fx + 30
            y: root.fy + 8
            width: root.fw - 96
            height: 22
            clip: true

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.alpha(Theme.bg_crust, 0.8)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Theme.bg_crust, 0.55)
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Qt.alpha(Theme.blue, 0.6)
            }

            Repeater {
                model: {
                    const step = 60, out = [];
                    for (let v = Math.ceil(root.tx / step) * step; v <= root.tx + root.tw; v += step) {
                        const p = v - h_ruler.x;
                        if (p > 16 && p < h_ruler.width - 16)
                            out.push({
                                v: v,
                                p: p
                            });
                    }
                    return out;
                }

                Text {
                    id: h_tick
                    required property var modelData
                    x: h_tick.modelData.p - h_tick.implicitWidth / 2
                    y: h_ruler.height - h_tick.implicitHeight - 5
                    text: root.pad4(h_tick.modelData.v + root.origin.x)
                    color: Theme.theme_primary_light
                    font.family: Style.mono_font
                    font.pixelSize: Style.fs(-8)

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.bottom
                        anchors.topMargin: 1
                        width: 1
                        height: 4
                        color: Theme.blue
                    }
                }
            }
        }

        Shape {
            visible: h_ruler.visible
            x: root.cx - 5
            y: root.fy + 8
            width: 10
            height: 5
            ShapePath {
                fillColor: Theme.theme_secondary
                strokeWidth: -1
                startX: 0
                startY: 0
                PathLine {
                    x: 10
                    y: 0
                }
                PathLine {
                    x: 5
                    y: 5
                }
                PathLine {
                    x: 0
                    y: 0
                }
            }
        }

        Item {
            id: v_ruler
            visible: root.fh > 160
            x: root.fx + root.fw - 42
            y: root.fy + 40
            width: 34
            height: root.fh - 90
            clip: true

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: Qt.alpha(Theme.bg_crust, 0.55)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Theme.bg_crust, 0.8)
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                width: 1
                height: parent.height
                color: Qt.alpha(Theme.blue, 0.6)
            }

            Repeater {
                model: {
                    const step = 50, out = [];
                    for (let v = Math.ceil(root.ty / step) * step; v <= root.ty + root.th; v += step) {
                        const p = v - v_ruler.y;
                        if (p > 10 && p < v_ruler.height - 10)
                            out.push({
                                v: v,
                                p: p
                            });
                    }
                    return out;
                }

                Text {
                    id: v_tick
                    required property var modelData
                    x: 7
                    y: v_tick.modelData.p - v_tick.implicitHeight / 2
                    text: root.pad4(v_tick.modelData.v + root.origin.y)
                    color: Theme.theme_primary_light
                    font.family: Style.mono_font
                    font.pixelSize: Style.fs(-8)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: -4
                        width: 4
                        height: 1
                        color: Theme.blue
                    }
                }
            }
        }

        Shape {
            visible: v_ruler.visible
            x: root.fx + root.fw - 42
            y: root.cy - 5
            width: 5
            height: 10
            ShapePath {
                fillColor: Theme.theme_secondary
                strokeWidth: -1
                startX: 0
                startY: 0
                PathLine {
                    x: 0
                    y: 10
                }
                PathLine {
                    x: 5
                    y: 5
                }
                PathLine {
                    x: 0
                    y: 0
                }
            }
        }

        Row {
            x: root.fx + 14
            y: root.fy + root.fh - 40
            height: 24
            spacing: 6

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: cam_row.implicitWidth + 12
                height: 20
                radius: 3
                border.width: 1
                border.color: Qt.alpha(Theme.blue, 0.65)
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.blue, 0.16))
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Theme.bg_crust, 0.9)
                    }
                }

                Rectangle {
                    x: 1
                    y: 1
                    width: parent.width - 2
                    height: 1
                    color: Qt.alpha(Theme.fg_strong, 0.18)
                }

                Row {
                    id: cam_row
                    anchors.centerIn: parent
                    spacing: 6

                    Binoculars {
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.blue
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "CAMERA"
                        color: Theme.fg_strong
                        font.family: Style.font_family
                        font.bold: true
                        font.letterSpacing: 1
                        font.pixelSize: Style.fs(-6)
                    }
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: cls_text.implicitWidth + 20
                height: 20
                radius: 3
                border.width: 1
                border.color: Qt.alpha(Theme.blue, 0.65)
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.blue, 0.16))
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Theme.bg_crust, 0.9)
                    }
                }

                Rectangle {
                    x: 1
                    y: 1
                    width: parent.width - 2
                    height: 1
                    color: Qt.alpha(Theme.fg_strong, 0.18)
                }

                Text {
                    id: cls_text
                    anchors.centerIn: parent
                    text: root.cls
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.bold: true
                    font.letterSpacing: 1
                    font.pixelSize: Style.fs(-6)
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: size_text.implicitWidth + 20
                height: 20
                radius: 3
                border.width: 1
                border.color: Qt.alpha(Theme.blue, 0.65)
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.blue, 0.16))
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Theme.bg_crust, 0.9)
                    }
                }

                Rectangle {
                    x: 1
                    y: 1
                    width: parent.width - 2
                    height: 1
                    color: Qt.alpha(Theme.fg_strong, 0.18)
                }

                Text {
                    id: size_text
                    anchors.centerIn: parent
                    text: Math.round(root.tw) + " x " + Math.round(root.th)
                    color: Theme.fg_strong
                    font.family: Style.mono_font
                    font.pixelSize: Style.fs(-4)
                }
            }
        }
    }
}
