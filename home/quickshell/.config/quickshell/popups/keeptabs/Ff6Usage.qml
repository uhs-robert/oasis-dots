import QtQuick
import QtQuick.Layouts
import qs.styles.snes.widgets as Snes
import qs.services
import qs.theme
import qs.features.clock

// The Usage tab as the FF6 Status screen: each limit a status line over an ATB gauge, resets as the next level up.
// Reads ClaudeUsageState directly; the contract is in UsageView.qml.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    Snes.SnesWindow {
        id: status_window
        anchors.fill: parent
    }

    ColumnLayout {
        x: 14
        y: 10
        width: status_window.width - 28 - status_window.drop
        height: status_window.height - 20 - status_window.drop
        spacing: 6

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: ClaudeUsageState.loading ? "Loading…" : ClaudeUsageState.error ? ClaudeUsageState.error : (ClaudeUsageState.updated > 0 ? "Claude usage · updated " + TimeFormat.format(new Date(ClaudeUsageState.updated)) : "Claude usage")
            color: ClaudeUsageState.error && !ClaudeUsageState.loading ? Theme.theme_label : Theme.theme_secondary
            style: Text.Raised
            styleColor: Style.text_shadow
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-2)
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 24
            visible: ClaudeUsageState.rows.length === 0 && !ClaudeUsageState.loading
            text: ClaudeUsageState.error ? "" : "No usage data yet"
            color: Theme.fg_strong
            style: Text.Raised
            styleColor: Style.text_shadow
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-1)
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: ClaudeUsageState.rows.length > 0
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            model: ClaudeUsageState.rows

            delegate: ColumnLayout {
                id: usage_row
                required property var modelData
                readonly property bool low: usage_row.modelData.percent >= 85

                width: ListView.view.width
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: usage_row.modelData.label.toUpperCase()
                        color: Theme.theme_primary_light
                        style: Text.Raised
                        styleColor: Style.text_shadow
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-2)
                    }

                    Text {
                        text: Math.round(usage_row.modelData.percent)
                        color: usage_row.low ? Theme.theme_label : Theme.fg_strong
                        style: Text.Raised
                        styleColor: Style.text_shadow
                        font.family: Style.number_font
                        font.pixelSize: root.st.fs(3)
                    }

                    Text {
                        text: "/100"
                        color: Theme.fg_strong
                        style: Text.Raised
                        styleColor: Style.text_shadow
                        font.family: Style.number_font
                        font.pixelSize: root.st.fs(-2)
                    }
                }

                Snes.SnesGauge {
                    Layout.fillWidth: true
                    implicitHeight: 8
                    value: usage_row.modelData.percent / 100
                    fill_color: usage_row.low ? Theme.theme_label : Theme.theme_primary_strong
                    shade_color: usage_row.low ? Qt.tint(Theme.theme_label, Qt.alpha(Theme.fg_strong, 0.4)) : Qt.tint(Theme.theme_primary_light, Qt.alpha(Theme.fg_strong, 0.3))
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    visible: usage_row.modelData.resets !== ""
                    text: "For level up: " + usage_row.modelData.resets
                    color: Theme.theme_secondary
                    style: Text.Raised
                    styleColor: Style.text_shadow
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-5)
                }
            }
        }
    }
}
