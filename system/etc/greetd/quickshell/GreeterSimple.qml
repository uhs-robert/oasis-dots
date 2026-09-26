// /etc/greetd/quickshell/GreeterSimple.qml
import QtQuick
import QtQuick.Layouts
import "theme"

// The plain login screen for styles without a lock skin: clock, date, user and a masked password line.
Item {
    id: root

    property var ctx: null
    readonly property color accent: root.ctx ? root.ctx.tint_bright : Theme.theme_primary
    readonly property real u: Math.min(root.width, root.height * 16 / 9) / 100

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.bg_core }
            GradientStop { position: 1; color: Theme.bg_crust }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: root.u * 1.2

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.ctx ? root.ctx.time_12 : ""
            color: Theme.fg_strong
            font.family: "Geist"
            font.pixelSize: root.u * 7
            font.weight: Font.Light
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.ctx ? root.ctx.date_text : ""
            color: root.accent
            font.family: "Geist"
            font.pixelSize: root.u * 1.6
        }

        Item {
            Layout.preferredHeight: root.u * 2
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.ctx ? root.ctx.user : ""
            color: Theme.fg_core
            font.family: "Geist"
            font.pixelSize: root.u * 1.8
            font.weight: Font.DemiBold
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.u * 24
            Layout.preferredHeight: root.u * 3.2
            radius: height / 2
            color: Qt.alpha(Theme.bg_crust, 0.7)
            border.width: 1
            border.color: root.ctx && root.ctx.failed ? Theme.error : root.accent

            Text {
                anchors.centerIn: parent
                text: {
                    const c = root.ctx;
                    if (!c) return "";
                    if (c.checking) return "Checking";
                    if (c.granted) return "Welcome back";
                    return c.buffer_length > 0 ? "•".repeat(Math.min(c.buffer_length, 24)) : "Password";
                }
                color: root.ctx && root.ctx.buffer_length > 0 ? Theme.fg_strong : Theme.fg_dim
                font.family: "Geist"
                font.pixelSize: root.u * 1.4
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: text !== ""
            text: {
                const c = root.ctx;
                if (!c) return "";
                if (c.caps_lock) return "Caps Lock is on";
                return c.message;
            }
            color: root.ctx && root.ctx.failed ? Theme.error : Theme.fg_dim
            font.family: "Geist"
            font.pixelSize: root.u * 1.1
        }
    }
}
