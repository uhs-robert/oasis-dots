// home/quickshell/.config/quickshell/bar/modules/Updates.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components"

BarModule {
    id: root
    module_name: "updates"

    readonly property int official_count: UpdatesState.official.length
    readonly property int aur_count: UpdatesState.aur.length

    shown: UpdatesState.available && (UpdatesState.total > 0 || UpdatesState.error !== "")
    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    tooltip_text: {
        const lines = ["Official: " + root.official_count, "AUR: " + root.aur_count];
        if (UpdatesState.checking) lines.push("Checking…");
        else if (UpdatesState.error) lines.push(UpdatesState.error);
        return lines.join("\n");
    }

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        BadgedGlyph {
            Layout.alignment: Qt.AlignVCenter
            visible: root.official_count > 0
            glyph: "󰮯"
            count: String(root.official_count)
        }

        BadgedGlyph {
            Layout.alignment: Qt.AlignVCenter
            visible: root.aur_count > 0
            glyph: "󰏗"
            count: String(root.aur_count)
        }

        // A failed check with no counts would otherwise leave an empty, clickable gap.
        BadgedGlyph {
            Layout.alignment: Qt.AlignVCenter
            visible: root.official_count === 0 && root.aur_count === 0 && UpdatesState.error !== ""
            glyph: "󰮯"
            count: "!"
            tint: Theme.warning
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                UpdatesState.refresh();
            } else {
                root.toggle_popup();
            }
        }
    }
}
