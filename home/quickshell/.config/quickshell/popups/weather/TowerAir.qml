import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// Air as PS2 glass panels over a tower field: the current AQI and pollutants in thin panels, then one tower per hour
// standing on the haze floor, coloured by AQI category. The cursor hour's tower is lit with its value above it.
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property var slice: WeatherState.aq_hours.slice(0, 24)
    // The cursor is shared with the longer hourly range, so it is clamped to these 24 hours.
    readonly property int cursor_index: Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))
    readonly property var cursor_row: root.slice[root.cursor_index]
    readonly property var current: WeatherState.aq_current
    readonly property color current_color: root.current ? WeatherState.aqi_color(root.current.aqi) : Style.text_dim

    readonly property real top_pad: 30
    readonly property real foot_h: 22
    readonly property real base_y: field.height - root.foot_h
    readonly property real col_w: root.slice.length > 0 ? field.width / root.slice.length : field.width
    readonly property real tower_w: Math.max(6, Math.min(24, root.col_w - 4))
    readonly property real axis_max: Math.max(100, ...root.slice.map(r => r.aqi))

    function height_of(aqi) {
        return Math.max(4, (root.base_y - root.top_pad) * (0.06 + 0.94 * Math.min(1, aqi / root.axis_max)));
    }

    function x_of(i) {
        return (i + 0.5) * root.col_w;
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const rows = root.slice;
        if (rows.length === 0) return;

        const base = root.base_y;
        const tw = root.tower_w;
        const font_px = Style.fs(-3);

        for (let i = 0; i < rows.length; i++) {
            const th = root.height_of(rows[i].aqi);
            const x = root.x_of(i) - tw / 2;
            const y = base - th;
            const accent = WeatherState.aqi_color(rows[i].aqi);

            const body = ctx.createLinearGradient(0, y, 0, base);
            body.addColorStop(0, Qt.alpha(accent, 0.55));
            body.addColorStop(0.35, Qt.alpha(accent, 0.34));
            body.addColorStop(1, Qt.alpha(accent, 0.1));
            ctx.fillStyle = body;
            ctx.fillRect(x, y, tw, th);

            ctx.fillStyle = Qt.alpha(Theme.bg_shadow, 0.28);
            ctx.fillRect(x + tw * 0.62, y, tw * 0.38, th);

            const bloom = ctx.createLinearGradient(0, y - 9, 0, y);
            bloom.addColorStop(0, Qt.alpha(accent, 0));
            bloom.addColorStop(1, Qt.alpha(accent, 0.3));
            ctx.fillStyle = bloom;
            ctx.fillRect(x - 2, y - 9, tw + 4, 9);

            ctx.fillStyle = Qt.alpha(accent, 0.95);
            ctx.fillRect(x, y, tw, 2);

            const reflection = ctx.createLinearGradient(0, base, 0, base + 7);
            reflection.addColorStop(0, Qt.alpha(accent, 0.28));
            reflection.addColorStop(1, Qt.alpha(accent, 0));
            ctx.fillStyle = reflection;
            ctx.fillRect(x, base, tw, 7);
        }

        ctx.font = font_px + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "center";
        const label_w = ctx.measureText(WeatherState.format_hour(new Date(2000, 0, 1, 12))).width + 10;
        const step = [1, 2, 3, 4, 6, 8, 12].find(n => n * root.col_w >= label_w) || 12;
        ctx.fillStyle = Theme.theme_primary_light;
        for (let i = 0; i < rows.length; i += step) {
            const text = WeatherState.format_hour(new Date(rows[i].dt));
            const half = ctx.measureText(text).width / 2;
            ctx.fillText(text, Math.max(half, Math.min(w - half, root.x_of(i))), h - 4);
        }
    }

    component Caption: Text {
        color: Theme.theme_primary_light
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.2
        elide: Text.ElideRight
    }

    component GlassPanel: Rectangle {
        radius: 8
        border.width: 1
        border.color: Qt.alpha(Theme.theme_primary_light, 0.22)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary_light, 0.14) }
            GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary_strong, 0.05) }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !WeatherState.aq_has_data
        text: WeatherState.aq_loading ? "Loading…" : "Air quality unavailable"
        color: Style.text_dim
        font.family: Style.font_family
        font.pixelSize: Style.font_size
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        visible: WeatherState.aq_has_data && !!root.current

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: readings.implicitHeight
            spacing: 6

            GlassPanel {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                Layout.fillHeight: true
                border.color: Qt.alpha(root.current_color, 0.55)

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Qt.alpha(root.current_color, 0.1)
                }

                RowLayout {
                    id: aqi_row
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        text: root.current ? root.current.aqi : "--"
                        color: root.current_color
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(14)
                        font.weight: Font.Light
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Caption { Layout.fillWidth: true; text: "US AQI" }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            text: root.current ? WeatherState.aqi_band(root.current.aqi).label : ""
                            color: Theme.fg_strong
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-1)
                        }
                    }
                }
            }

            ColumnLayout {
                id: readings
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                spacing: 4

                Repeater {
                    model: [
                        { label: "PM2.5", value: root.current ? root.current.pm25 : null },
                        { label: "PM10", value: root.current ? root.current.pm10 : null },
                        { label: "Ozone", value: root.current ? root.current.ozone : null }
                    ]

                    GlassPanel {
                        id: reading
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: reading_value.implicitHeight + 6
                        radius: 6

                        Caption {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: reading.modelData.label
                        }

                        Text {
                            id: reading_value
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: reading.modelData.value !== null ? reading.modelData.value.toFixed(1) : "--"
                            color: Theme.fg_strong
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-1)
                            font.weight: Font.Light
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            readonly property var r: root.cursor_row
            text: r ? WeatherState.format_hour(new Date(r.dt)) + " · AQI " + r.aqi + " · " + WeatherState.aqi_band(r.aqi).label : ""
            color: Theme.fg_strong
            font.family: Style.font_family
            font.pixelSize: Style.fs(-2)
            font.weight: Font.Light
        }

        Item {
            id: field
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: 4

            TowerFloor {
                y: root.base_y - 28
                width: parent.width
                height: parent.height - y
                haze_h: 28
            }

            Canvas {
                id: canvas
                anchors.fill: parent
                onPaint: root.paint(getContext("2d"), width, height)
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                Connections {
                    target: root
                    function onSliceChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: TimeFormat
                    function onH24Changed() { canvas.requestPaint(); }
                }
                Connections {
                    target: Style
                    function onFont_familyChanged() { canvas.requestPaint(); }
                    function onFont_sizeChanged() { canvas.requestPaint(); }
                    function onPalChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: Theme
                    function onTheme_primary_lightChanged() { canvas.requestPaint(); }
                    function onTheme_primary_strongChanged() { canvas.requestPaint(); }
                    function onBg_shadowChanged() { canvas.requestPaint(); }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: mouse => {
                    if (root.slice.length === 0) return;
                    root.on_select(Math.max(0, Math.min(root.slice.length - 1, Math.floor(mouse.x / root.col_w))));
                }
            }

            Item {
                id: lit
                readonly property real th: root.cursor_row ? root.height_of(root.cursor_row.aqi) : 0
                readonly property color accent: root.cursor_row ? WeatherState.aqi_color(root.cursor_row.aqi) : Theme.info
                visible: !!root.cursor_row
                x: root.x_of(root.cursor_index) - root.tower_w / 2
                y: root.base_y - lit.th
                width: root.tower_w
                height: lit.th

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -5
                    anchors.bottomMargin: 0
                    radius: 7
                    color: Qt.alpha(lit.accent, 0.22)
                }

                Rectangle {
                    anchors.fill: parent
                    border.width: 1
                    border.color: Qt.alpha(Theme.theme_primary_light, 0.85)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.alpha(Theme.fg_strong, 0.4) }
                        GradientStop { position: 1; color: Qt.alpha(lit.accent, 0.12) }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 2
                    color: Qt.lighter(lit.accent, 1.4)
                }

                Rectangle {
                    // Kept inside the field so the end hours' pills are not cut off.
                    x: Math.max(-lit.x, Math.min(field.width - lit.x - width, (lit.width - width) / 2))
                    y: -height - 3
                    width: Math.max(root.tower_w + 12, value_text.implicitWidth + 14)
                    height: value_text.implicitHeight + 6
                    radius: height / 2
                    color: Style.frame_color
                    border.width: 1
                    border.color: Qt.alpha(lit.accent, 0.8)

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Qt.alpha(lit.accent, 0.22)
                    }

                    Text {
                        id: value_text
                        anchors.centerIn: parent
                        text: root.cursor_row ? root.cursor_row.aqi : ""
                        color: Theme.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(0)
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }
}
