import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "KeeptabsFormat.js" as Fmt

// The Usage tab as Activity rings: one concentric ring per usage row, with a legend beside them. Same contract as UsageView.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    // Only four rings fit; the legend still lists every row.
    readonly property var rows: ClaudeUsageState.rows
    readonly property var ring_rows: root.rows.slice(0, 4)
    readonly property real ring_size: Style.px(150)
    readonly property real ring_width: Style.px(12)
    readonly property real ring_gap: Style.px(3)

    // Over 85% a ring is an error, otherwise the row keeps its own hue.
    function ring_color(i, percent) {
        if (percent > 85) return Style.pal.error;
        return [Style.pal.label, Style.pal.ok, Style.pal.info, Style.pal.warning][i % 4];
    }

    // Rows past the rings get a neutral swatch so they do not read as a ring.
    function legend_color(i, percent) {
        return i < 4 ? root.ring_color(i, percent) : percent > 85 ? Style.pal.error : root.st.text_dim;
    }

    onRowsChanged: rings.requestPaint()

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

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

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 24
            visible: ClaudeUsageState.rows.length === 0 && !ClaudeUsageState.loading
            text: ClaudeUsageState.error ? "" : "No usage data yet"
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-1)
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: ClaudeUsageState.rows.length > 0

            Canvas {
                id: rings
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.ring_size
                height: root.ring_size

                // Qt.alpha and the percent values are read in onPaint, so repaint when any input changes.
                property var ring_colors: root.ring_rows.map((r, i) => root.ring_color(i, r.percent))
                onRing_colorsChanged: requestPaint()
                onWidthChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.lineCap = "round";
                    const c = width / 2;
                    const start = -Math.PI / 2;
                    for (let i = 0; i < root.ring_rows.length; i++) {
                        const r = c - root.ring_width / 2 - i * (root.ring_width + root.ring_gap);
                        if (r <= 0) break;
                        const pct = Math.max(0, Math.min(100, root.ring_rows[i].percent));
                        ctx.lineWidth = root.ring_width;
                        ctx.strokeStyle = Qt.alpha(ring_colors[i], 0.2);
                        ctx.beginPath();
                        ctx.arc(c, c, r, 0, Math.PI * 2);
                        ctx.stroke();
                        if (pct <= 0) continue;
                        ctx.strokeStyle = ring_colors[i];
                        ctx.beginPath();
                        ctx.arc(c, c, r, start, start + Math.PI * 2 * pct / 100);
                        ctx.stroke();
                    }
                }
            }

            Flickable {
                id: legend_flick
                anchors.left: rings.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                clip: true
                contentHeight: Math.max(legend_column.implicitHeight, legend_flick.height)
                interactive: legend_column.implicitHeight > legend_flick.height
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: legend_column
                    width: legend_flick.width
                    y: Math.max(0, (legend_flick.height - implicitHeight) / 2)
                    spacing: 10

                    Repeater {
                        model: root.rows

                        delegate: RowLayout {
                            id: legend
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                Layout.preferredWidth: 6
                                Layout.preferredHeight: Style.px(32)
                                Layout.alignment: Qt.AlignTop
                                radius: 3
                                color: legend.index < 4 ? root.ring_color(legend.index, legend.modelData.percent) : root.st.text_dim
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 1

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        text: legend.modelData.label.replace(/^Current /, "")
                                        color: root.st.text_fg
                                        font.family: root.st.font_family
                                        font.pixelSize: root.st.fs(-2)
                                        font.bold: true
                                    }

                                    Text {
                                        text: legend.modelData.percent + "%"
                                        color: root.legend_color(legend.index, legend.modelData.percent)
                                        font.family: root.st.mono_font
                                        font.pixelSize: root.st.fs(-2)
                                        font.bold: true
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                    visible: legend.modelData.resets !== ""
                                    text: "Resets " + legend.modelData.resets
                                    color: root.st.text_dim
                                    font.family: root.st.font_family
                                    font.pixelSize: root.st.fs(-3)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
