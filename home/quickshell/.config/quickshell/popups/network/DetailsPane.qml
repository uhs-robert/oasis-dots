// home/quickshell/.config/quickshell/popups/network/DetailsPane.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"

ColumnLayout {
    id: root

    property var st
    property var target: null
    property string ssid: ""
    property bool loaded: false
    property var profile: null
    property var rows: []
    property int setting_selected: 0
    property bool dns_edit_mode: false
    property string dns_text: ""
    property bool saving: false
    property string setting_error: ""
    property var metered_labels: ({})

    signal activate(int i)
    signal dns_edited(string t)
    signal dns_finished(bool apply)

    function focus_dns() {
        dns_input.forceActiveFocus();
    }

    spacing: 6

    Text {
        visible: !root.target
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: "Select a network in the list to see its details"
        color: root.st.text_muted
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    Repeater {
        model: root.rows

        Item {
            id: detail_row
            required property var modelData

            Layout.fillWidth: true
            implicitHeight: Math.max(detail_label.implicitHeight, detail_value.implicitHeight)

            Text {
                id: detail_label
                text: detail_row.modelData.label
                color: root.st.text_muted
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }

            Text {
                id: detail_value
                x: detail_label.implicitWidth + 12
                width: Math.max(0, detail_row.width - x)
                horizontalAlignment: Text.AlignRight
                wrapMode: detail_row.modelData.wrap ? Text.Wrap : Text.NoWrap
                elide: detail_row.modelData.wrap ? Text.ElideNone : Text.ElideRight
                text: detail_row.modelData.value
                color: root.st.text_fg
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }
        }
    }

    MenuSection {
        visible: !!root.target
        Layout.fillWidth: true
        topPadding: 4
        label: "Settings"
    }

    Text {
        visible: !!root.target && !root.profile
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: !root.target || !root.target.known ? "Connect to edit settings" : root.loaded ? "No saved profile found" : "Loading…"
        color: root.st.text_muted
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    ToggleRow {
        visible: !!root.profile
        label: "Autoconnect"
        toggle_key: ""
        checked: !!root.profile && root.profile.autoconnect
        selected: root.setting_selected === 0
        onToggled: root.activate(0)
    }

    ToggleRow {
        visible: !!root.profile
        label: "Metered"
        toggle_key: ""
        checked: !!root.profile && root.profile.metered === "yes"
        state_label: root.profile ? root.metered_labels[root.profile.metered] || "Auto" : ""
        selected: root.setting_selected === 1
        onToggled: root.activate(1)
    }

    MenuRow {
        id: dns_row
        readonly property real pad: dns_row.st.toggle_brackets ? 6 : 0
        visible: !!root.profile && !root.dns_edit_mode
        Layout.fillWidth: true
        implicitHeight: Math.max(dns_row.st.toggle_brackets ? Style.px(22) : 0, Math.max(dns_label.implicitHeight, dns_value.implicitHeight) + dns_row.pad)
        selected: root.setting_selected === 2

        Text {
            id: dns_label
            x: dns_row.pad + dns_row.inset
            y: dns_value.y
            text: "DNS"
            color: dns_row.fg(root.st.text_strong)
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-1)
        }

        Text {
            id: dns_value
            x: dns_label.x + dns_label.implicitWidth + 12
            y: (dns_row.height - height) / 2
            width: Math.max(0, dns_row.width - x - dns_row.pad - dns_row.key_space)
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.Wrap
            text: root.profile && root.profile.dns.length > 0 ? root.profile.dns.join("\n") : "Auto"
            color: dns_row.fg(root.profile && root.profile.dns.length > 0 ? root.st.text_fg : root.st.toggle_off)
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-2)
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.activate(2)
        }
    }

    ColumnLayout {
        visible: root.dns_edit_mode
        Layout.fillWidth: true
        spacing: 6

        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: "DNS for " + root.ssid
            color: root.st.text_strong
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-1)
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Style.px(26)
            radius: Style.radius(4)
            color: Style.pal.bg_surface

            TextInput {
                id: dns_input
                anchors.fill: parent
                anchors.margins: 6
                clip: true
                color: root.st.text_fg
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-1)
                text: root.dns_text
                onTextChanged: root.dns_edited(text)

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.dns_finished(true);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.dns_finished(false);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                        event.accepted = true;
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "Separate with spaces; leave blank for automatic"
            color: root.st.text_muted
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-3)
        }

        MenuFooter {
            Layout.fillWidth: true
            wrap: true
            text: "Enter apply · Esc cancel"
        }
    }

    Text {
        visible: root.saving
        text: root.profile && root.profile.active ? "Applying…" : "Saving…"
        color: root.st.text_muted
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }

    Text {
        visible: root.setting_error !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: root.setting_error
        color: Style.pal.warning
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
