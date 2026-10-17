pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.theme
import qs.services
import qs.styles.halflife.widgets
import qs.features.clock
import "KeeptabsFormat.js" as Fmt

// The Usage tab as the bottom of the HEV HUD: the session limit is HEALTH, the weekly limit SUIT, any other limit an
// ammo-style bar, and an HEV voice line comes up while ClaudeUsageState has a warning. Contract as in UsageView.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_primary, text_dim: root.st.text_dim })
    readonly property color hl: Style.text_primary
    readonly property color hl_t: Style.text_muted
    // Other styles leave these tokens transparent, so a borrowed layout falls back to the palette.
    readonly property color hairline: Style.hairline.a > 0 ? Style.hairline : Qt.alpha(Style.pal.fg_strong, 0.55)

    readonly property var rows: ClaudeUsageState.rows
    readonly property var session_row: root.rows.find(r => /session/i.test(r.label)) || null
    readonly property var weekly_row: root.rows.find(r => /week/i.test(r.label) && r !== root.session_row) || null
    readonly property var extra_rows: root.rows.filter(r => r !== root.session_row && r !== root.weekly_row)

    readonly property bool alarm: ClaudeUsageState.warning
    readonly property color voice_color: root.alarm ? Theme.theme_label : root.hl
    readonly property string voice_text: {
        if (!root.alarm) return "";
        const label = ClaudeUsageState.warnings[0].label;
        if (/session/i.test(label)) return "WARNING: SESSION RESERVES CRITICAL";
        if (/week/i.test(label)) return "WARNING: WEEKLY RESERVES CRITICAL";
        return "WARNING: " + label.toUpperCase() + " RESERVES LOW";
    }

    function charger_text(row) {
        return row && row.resets !== "" ? "HEV CHARGER ONLINE " + row.resets.toUpperCase() : "HEV CHARGER OFFLINE";
    }

    function remaining(row) {
        return row ? Math.max(0, Math.min(100, 100 - row.percent)) : 0;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: ClaudeUsageState.loading ? "Loading…" : ClaudeUsageState.error ? ClaudeUsageState.error : (ClaudeUsageState.updated > 0 ? "Claude usage · updated " + TimeFormat.format(new Date(ClaudeUsageState.updated)) : "Claude usage")
            color: ClaudeUsageState.error && !ClaudeUsageState.loading ? Style.pal.warning : root.st.text_muted
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-2)
            font.bold: true
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: voice_row.implicitHeight + 8
            visible: root.alarm
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.alpha(root.voice_color, 0.13) }
                GradientStop { position: 1; color: "transparent" }
            }

            Rectangle {
                width: 2
                height: parent.height
                color: root.voice_color
            }

            RowLayout {
                id: voice_row
                x: 8
                width: parent.width - 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Item {
                    Layout.preferredWidth: 13
                    Layout.preferredHeight: 12
                    Layout.alignment: Qt.AlignVCenter

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: -1
                            fillColor: root.voice_color
                            PathPolyline { path: [Qt.point(6.5, 0), Qt.point(13, 12), Qt.point(0, 12), Qt.point(6.5, 0)] }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -1
                        text: "!"
                        color: Theme.bg_crust
                        font.family: Style.number_font
                        font.pixelSize: 9
                        font.bold: true
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.WordWrap
                    text: root.voice_text
                    color: root.voice_color
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-5)
                    font.bold: true
                    font.letterSpacing: 1.3
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 24
            visible: root.rows.length === 0 && !ClaudeUsageState.loading
            text: ClaudeUsageState.error ? "" : "No usage data yet"
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-1)
        }

        // Limits beyond session and week, as ammo reserves above the HUD.
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.extra_rows.length > 0
            clip: true
            spacing: 6
            model: root.extra_rows
            boundsBehavior: Flickable.StopAtBounds

            delegate: ColumnLayout {
                id: extra
                required property var modelData
                width: ListView.view.width
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: extra.modelData.label.toUpperCase()
                        color: root.hl_t
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-5)
                        font.bold: true
                        font.letterSpacing: 1.5
                    }

                    Text {
                        text: extra.modelData.percent + "% used"
                        color: Fmt.context_bar_color(extra.modelData.percent, root.colors)
                        font.family: Style.number_font
                        font.pixelSize: root.st.fs(-3)
                        font.bold: true
                    }
                }

                SkewBar {
                    Layout.fillWidth: true
                    Layout.rightMargin: 5
                    cells: 24
                    implicitHeight: 8
                    value: extra.modelData.percent / 100
                    on_color: Fmt.context_bar_color(extra.modelData.percent, root.colors)
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: root.charger_text(extra.modelData)
                    color: root.st.text_dim
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-5)
                    font.letterSpacing: 1
                }
            }
        }

        Item {
            Layout.fillHeight: true
            visible: root.extra_rows.length === 0
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: root.hairline
        }

        // The divider's fillHeight would otherwise make the whole HUD row soak up the spare height.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 14

            Gauge {
                label: "HEALTH"
                row: root.session_row
                icon_cross: true
            }

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: root.hairline
            }

            Gauge {
                label: "SUIT"
                row: root.weekly_row
                icon_cross: false
            }
        }
    }

    // One HUD readout: icon, remaining percent, a skewed bar, the caption and the charger line.
    component Gauge: ColumnLayout {
        id: gauge
        property string label: ""
        property var row: null
        property bool icon_cross: true
        readonly property real remaining_pct: root.remaining(gauge.row)
        readonly property color tone: gauge.row ? Fmt.context_bar_color(gauge.row.percent, root.colors) : root.hl

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.minimumWidth: 0
        Layout.alignment: Qt.AlignTop
        spacing: 4

        RowLayout {
            spacing: 8

            Item {
                id: icon
                Layout.preferredWidth: 26
                Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                readonly property real fill_top: 28 * (1 - gauge.remaining_pct / 100)

                Shape {
                    visible: gauge.icon_cross
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: -1
                        fillColor: gauge.tone
                        PathSvg { path: "M8.5 3h7v7.5H23v7h-7.5V25h-7v-7.5H1v-7h7.5z" }
                    }
                }

                Item {
                    visible: !gauge.icon_cross
                    anchors.fill: parent

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: 1.5
                            strokeColor: root.hairline
                            fillColor: "transparent"
                            PathSvg { path: "M12 1.5 22 5.5v8.5c0 6-4.4 10.4-10 12.5C6.4 24.4 2 20 2 14V5.5z" }
                        }
                    }

                    // The shield fills from the bottom up with what remains.
                    Item {
                        y: icon.fill_top
                        width: parent.width
                        height: parent.height - icon.fill_top
                        // A zero-height clip does not clip at all, so an empty shield would draw full.
                        visible: height > 0
                        clip: true

                        Shape {
                            y: -icon.fill_top
                            width: icon.width
                            height: icon.height
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeWidth: -1
                                fillColor: gauge.tone
                                PathSvg { path: "M12 1.5 22 5.5v8.5c0 6-4.4 10.4-10 12.5C6.4 24.4 2 20 2 14V5.5z" }
                            }
                        }
                    }
                }
            }

            Row {
                spacing: 2

                Text {
                    text: gauge.row ? String(Math.round(gauge.remaining_pct)) : "--"
                    color: gauge.tone
                    font.family: Style.number_font
                    font.pixelSize: 34
                    font.bold: true
                    lineHeight: 0.9
                }

                Text {
                    text: "%"
                    color: root.hl_t
                    font.family: Style.number_font
                    font.pixelSize: 12
                    font.bold: true
                }
            }
        }

        SkewBar {
            Layout.fillWidth: true
            Layout.rightMargin: 5
            cells: 10
            value: gauge.remaining_pct / 100
            on_color: gauge.tone
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: gauge.label + (gauge.row ? "  ·  " + gauge.row.percent + "% used" : "")
            color: root.hl_t
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-6)
            font.bold: true
            font.letterSpacing: 2
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: root.charger_text(gauge.row)
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-5)
            font.letterSpacing: 1
        }
    }
}
