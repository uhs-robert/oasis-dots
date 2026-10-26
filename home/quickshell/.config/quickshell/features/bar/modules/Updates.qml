import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.features.updates
import qs.features.bar

BarModule {
    id: root
    module_name: "updates"
    hover_popup: true

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

    ModuleRow {
        id: row
        vertical: root.vertical
        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        spacing: root.vertical ? 4 : 10

        BadgedGlyph {
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            vertical: root.vertical
            cross: root.cross
            visible: root.official_count > 0
            icon_name: "updates"
            icon_variant: "official"
            glyph: "󰮯"
            count: String(root.official_count)
        }

        BadgedGlyph {
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            vertical: root.vertical
            cross: root.cross
            visible: root.aur_count > 0
            icon_name: "updates"
            icon_variant: "aur"
            glyph: "󰏗"
            count: String(root.aur_count)
        }

        // A failed check with no counts would otherwise leave an empty, clickable gap.
        BadgedGlyph {
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            vertical: root.vertical
            cross: root.cross
            visible: root.official_count === 0 && root.aur_count === 0 && UpdatesState.error !== ""
            icon_name: "updates"
            icon_variant: "official"
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
