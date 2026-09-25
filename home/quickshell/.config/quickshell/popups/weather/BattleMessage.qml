// home/quickshell/.config/quickshell/popups/weather/BattleMessage.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"

// The first active alert as a battle message: a small centred window with a red orb, the event and when it ends.
Item {
    id: root

    property var alert: WeatherState.alerts.length > 0 ? WeatherState.alerts[0] : null
    property int more: Math.max(0, WeatherState.alerts.length - 1)
    signal clicked()

    readonly property color orb_color: Style.materia.alert !== undefined ? Style.materia.alert : Theme.theme_label

    implicitHeight: body.implicitHeight + 12

    Rectangle {
        id: box
        anchors.fill: parent
        anchors.leftMargin: Math.min(24, root.width * 0.06)
        anchors.rightMargin: anchors.leftMargin
        radius: 5
        color: Style.frame_color
        border.width: 2
        border.color: Style.frame_border_color

        WindowGradient {
            anchors.fill: parent
            anchors.margins: 2
            top_radius: 3
            bottom_radius: 3
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 3
            color: "transparent"
            border.width: 1
            border.color: Style.frame_inset_color
        }
    }

    ColumnLayout {
        id: body
        anchors.centerIn: box
        width: Math.min(implicitWidth, box.width - 20)
        spacing: 0

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: body.width
            spacing: 6

            MateriaOrb {
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                color: root.orb_color
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.alert ? root.alert.event : ""
                color: Qt.tint(Theme.fg_strong, Qt.alpha(Theme.theme_label, 0.45))
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
                font.weight: Font.ExtraBold
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: body.width
            elide: Text.ElideRight
            visible: text !== ""
            text: !root.alert ? "" : [root.alert.ends ? "until " + WeatherState.fmt_location_time(new Date(root.alert.ends)) : "", root.more > 0 ? "+" + root.more + " more" : ""].filter(s => s !== "").join("  ")
            color: Theme.theme_primary_light
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
            font.weight: Font.DemiBold
        }
    }

    MouseArea {
        anchors.fill: box
        onClicked: root.clicked()
    }
}
