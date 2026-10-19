import QtQuick
import QtQuick.Layouts
import qs.ui.effects
import qs.theme
import qs.styles.crt.widgets
import qs.features.popups
import "KeeptabsFormat.js" as Fmt

// CRT: the WeatherStar 4000 "Latest Observations" page. A table pages as many sessions as fit, the page
// following `selected`; the selected session's detail sits in a "Local Forecast" band and the LDL crawl
// scrolls the sessions that wait. Contract as in AgentsView.
Item {
    id: root

    property var sessions: []
    property int selected: 0
    property int pick_exit: 0
    property var st: Style
    property var on_select: function (i) {}
    property var on_activate: function (id) {}
    property bool draws_footer: false

    // As many rows as the table panel holds (header and 2 px spacing included), so rows never squeeze when
    // the crawl shows or the title wraps.
    readonly property int page_size: Math.max(3, Math.floor((table_panel.height - 16 - table_header.implicitHeight - 2) / (root.row_h + 2)))
    readonly property int page_count: Math.max(1, Math.ceil(root.sessions.length / root.page_size))
    readonly property int page: Math.min(root.page_count - 1, Math.floor(Math.max(0, root.selected) / root.page_size))
    readonly property var visible_rows: root.sessions.slice(root.page * root.page_size, (root.page + 1) * root.page_size)
    readonly property var current: root.sessions[root.selected] || null
    readonly property int row_px: root.st.fs(-3)
    readonly property int row_h: Style.px(22)
    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: Theme.fg_strong, text_dim: root.st.text_dim })
    readonly property var cond_words: ({ waiting: "Waiting", done: "Done", running: "Busy" })
    readonly property var waiting_names: root.sessions.filter(s => s.state === "waiting").map(s => s.project || s.title || "Untitled")
    readonly property string crawl_text: root.waiting_names.map(n => n + " is waiting for input...").join("     ") + "     "

    // The page follows `selected`, so there is nothing to scroll.
    function ensure_visible(i) {}

    function cond(state) {
        return root.cond_words[state] || "Idle";
    }

    function has_pct(s) {
        return s.context_pct !== null && s.context_pct !== undefined;
    }

    FontMetrics {
        id: metrics
        font.family: root.st.font_family
        font.pixelSize: root.row_px
    }

    Text {
        anchors.centerIn: parent
        visible: root.sessions.length === 0
        text: root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed"
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    ColumnLayout {
        anchors.fill: parent
        visible: root.sessions.length > 0
        spacing: 4

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: "Agent Observations"
                color: Theme.theme_secondary
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-1)
                style: Text.Outline
                styleColor: Theme.bg_shadow
            }

            Text {
                visible: root.page_count > 1
                text: "Page " + (root.page + 1) + "/" + root.page_count
                color: Theme.fg_strong
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-4)
                style: Text.Outline
                styleColor: Theme.bg_shadow
            }
        }

        Item {
            id: table_panel
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0

            WsPanel {
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 2

                RowLayout {
                    id: table_header
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: "Project"
                        color: Theme.theme_secondary
                        font.family: root.st.font_family
                        font.pixelSize: root.row_px
                        style: Text.Outline
                        styleColor: Theme.bg_shadow
                    }

                    Text {
                        Layout.preferredWidth: metrics.advanceWidth("Waiting")
                        text: "Cond"
                        color: Theme.theme_secondary
                        font.family: root.st.font_family
                        font.pixelSize: root.row_px
                        style: Text.Outline
                        styleColor: Theme.bg_shadow
                    }

                    Text {
                        Layout.preferredWidth: metrics.advanceWidth("100%")
                        horizontalAlignment: Text.AlignRight
                        text: "Ctx"
                        color: Theme.theme_secondary
                        font.family: root.st.font_family
                        font.pixelSize: root.row_px
                        style: Text.Outline
                        styleColor: Theme.bg_shadow
                    }

                    Text {
                        Layout.preferredWidth: metrics.advanceWidth("99m")
                        horizontalAlignment: Text.AlignRight
                        text: "Age"
                        color: Theme.theme_secondary
                        font.family: root.st.font_family
                        font.pixelSize: root.row_px
                        style: Text.Outline
                        styleColor: Theme.bg_shadow
                    }
                }

                Repeater {
                    model: root.visible_rows

                    Item {
                        id: obs_row
                        required property var modelData
                        required property int index
                        readonly property int session_index: root.page * root.page_size + obs_row.index
                        readonly property bool is_selected: obs_row.session_index === root.selected

                        Layout.fillWidth: true
                        Layout.preferredHeight: root.row_h

                        WsPanel {
                            anchors.fill: parent
                            visible: obs_row.is_selected
                            lit: true
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                text: obs_row.modelData.project || obs_row.modelData.title || "Untitled"
                                color: Theme.fg_strong
                                font.family: root.st.font_family
                                font.pixelSize: root.row_px
                                style: Text.Outline
                                styleColor: Theme.bg_shadow
                            }

                            Text {
                                Layout.preferredWidth: metrics.advanceWidth("Waiting")
                                text: root.cond(obs_row.modelData.state)
                                color: Fmt.state_color(obs_row.modelData.state, root.colors)
                                font.family: root.st.font_family
                                font.pixelSize: root.row_px
                                style: Text.Outline
                                styleColor: Theme.bg_shadow
                            }

                            Text {
                                Layout.preferredWidth: metrics.advanceWidth("100%")
                                horizontalAlignment: Text.AlignRight
                                text: root.has_pct(obs_row.modelData) ? obs_row.modelData.context_pct + "%" : "--"
                                color: root.has_pct(obs_row.modelData) ? Fmt.context_bar_color(obs_row.modelData.context_pct, root.colors) : root.st.text_dim
                                font.family: root.st.font_family
                                font.pixelSize: root.row_px
                                style: Text.Outline
                                styleColor: Theme.bg_shadow
                            }

                            Text {
                                Layout.preferredWidth: metrics.advanceWidth("99m")
                                horizontalAlignment: Text.AlignRight
                                text: Fmt.age(obs_row.modelData.since)
                                color: Theme.fg_strong
                                font.family: root.st.font_family
                                font.pixelSize: root.row_px
                                style: Text.Outline
                                styleColor: Theme.bg_shadow
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.on_select(obs_row.session_index);
                                root.on_activate(obs_row.modelData.id);
                            }
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }

            Scanlines {
                anchors.fill: parent
                visible: root.st.scanlines
                color: root.st.scanline_color
                period: root.st.scanline_period
            }
        }

        Text {
            text: "Local Forecast"
            color: Theme.theme_secondary
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-3)
            style: Text.Outline
            styleColor: Theme.bg_shadow
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: forecast_text.implicitHeight + 12

            WsPanel {
                anchors.fill: parent
            }

            ColumnLayout {
                id: forecast_text
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.current ? (root.current.title || "Untitled") : ""
                    color: Theme.fg_strong
                    font.family: root.st.font_family
                    font.pixelSize: root.row_px
                    style: Text.Outline
                    styleColor: Theme.bg_shadow
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: root.current ? (root.current.agent || "claude") + " · " + (root.current.where || "") + (root.has_pct(root.current) ? " · " + Fmt.fmt_tokens(root.current.context_used) + "/" + Fmt.fmt_tokens(root.current.context_window) : "") : ""
                    color: Theme.theme_primary_light
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-4)
                    style: Text.Outline
                    styleColor: Theme.bg_shadow
                }
            }
        }

        Item {
            id: crawl
            readonly property bool active: root.waiting_names.length > 0
            // Held off for a frame whenever the text changes: a running NumberAnimation keeps its old `to` and
            // `duration`, so the loop would jump at the seam.
            property bool reset: false
            readonly property bool running: crawl.active && root.visible && Popups.open_name === "keeptabs" && !crawl.reset
            readonly property int copies: crawl_metrics.advanceWidth > 0 ? Math.ceil(crawl.width / crawl_metrics.advanceWidth) + 1 : 1

            visible: crawl.active
            Layout.fillWidth: true
            Layout.preferredHeight: crawl.active ? crawl_metrics.height + 4 : 0
            clip: true

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(Theme.bg_shadow, 0.7)
            }

            TextMetrics {
                id: crawl_metrics
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-4)
                text: root.crawl_text
                onAdvanceWidthChanged: {
                    crawl.reset = true;
                    Qt.callLater(() => crawl.reset = false);
                }
            }

            Row {
                id: crawl_row
                y: 2

                NumberAnimation on x {
                    running: crawl.running
                    from: 0
                    to: -crawl_metrics.advanceWidth
                    duration: Math.max(1, crawl_metrics.advanceWidth / 0.04)
                    loops: Animation.Infinite
                }

                Repeater {
                    model: crawl.copies

                    Text {
                        text: root.crawl_text
                        color: Theme.fg_strong
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }
                }
            }
        }
    }
}
