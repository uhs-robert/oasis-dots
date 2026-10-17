import QtQuick
import QtQuick.Layouts
import qs.components
import qs.ui.frames
import qs.theme
import qs.services

// A Scan Visor logbook entry, "Atmospheric toxicity": the AQI as a contamination level, the pollutants as analysed compounds with scan bars,
// and the 24 hours as a trace with the cursor hour locked on. h/l move the hour cursor.
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property color visor: Style.pal.primary
    readonly property color visor_light: Style.pal.primary_light
    readonly property color warning: Theme.theme_label
    readonly property bool shown: root.visible && Popups.open_name === "weather"

    readonly property var slice: WeatherState.aq_hours.slice(0, 24)
    // The cursor is shared with the longer hourly range, so it is clamped to these 24 hours.
    readonly property int cursor_index: Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))
    readonly property var cursor_row: root.slice[root.cursor_index]

    readonly property var cur: WeatherState.aq_current
    readonly property bool ready: WeatherState.aq_has_data && !!root.cur
    readonly property int unhealthy_from: 151
    readonly property int aqi: root.cur ? root.cur.aqi : -1
    readonly property bool contaminated: root.aqi >= root.unhealthy_from
    readonly property color lock_color: root.contaminated ? root.warning : root.visor

    // Concentration (ug/m3) at which each compound reaches the US AQI's "unhealthy" band; the bar's full scale is twice that.
    readonly property var compounds: [
        { name: "PM2.5", note: "FINE DUST", key: "pm25", limit: 55.4 },
        { name: "PM10", note: "COARSE DUST", key: "pm10", limit: 154 },
        { name: "O3", note: "OZONE", key: "ozone", limit: 165 }
    ]

    readonly property int trace_top: 14
    readonly property int trace_bottom: 18
    readonly property real trace_max: Math.max(150, ...root.slice.map(r => r.aqi)) * 1.08

    function trace_y(aqi, h) {
        const plot_h = h - root.trace_top - root.trace_bottom;
        return root.trace_top + plot_h - Math.min(1, aqi / root.trace_max) * plot_h;
    }

    Text {
        anchors.centerIn: parent
        visible: !root.ready
        text: WeatherState.aq_loading ? "ACQUIRING SCAN DATA…" : "SCAN FAILED · AIR QUALITY UNAVAILABLE"
        color: Style.text_dim
        font.family: Style.font_family
        font.pixelSize: Style.fs(-2)
        font.letterSpacing: 1.5
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        visible: root.ready

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "SCAN COMPLETE"
                color: root.visor
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 2.5
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: "AIR TOXICITY"
                color: Style.pal.fg_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 2.5
            }

            Text {
                visible: root.contaminated
                text: "▲ CONTAMINATED"
                color: root.warning
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 1.5

                SequentialAnimation on opacity {
                    running: root.shown && root.contaminated
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: -4
            Layout.preferredHeight: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.alpha(root.lock_color, 0.6) }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        // Contamination level: the AQI locked in brackets beside its band and a segmented gauge across the 0-300 scale.
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Item {
                Layout.preferredWidth: aqi_text.implicitWidth + 24
                Layout.preferredHeight: 52
                Layout.alignment: Qt.AlignTop

                Rectangle {
                    anchors.fill: parent
                    color: Qt.alpha(root.lock_color, 0.07)
                }

                CornerBrackets {
                    anchors.fill: parent
                    color: root.lock_color
                    inset: 0
                    arm: 9
                    thickness: 1.5
                    all_corners: true
                }

                Text {
                    id: aqi_text
                    anchors.centerIn: parent
                    text: root.aqi
                    color: WeatherState.aqi_color(root.aqi)
                    font.family: Style.number_font
                    font.pixelSize: Style.fs(14)
                    font.bold: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 3

                Text {
                    text: "CONTAMINATION LEVEL · US AQI"
                    color: root.visor
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                    font.letterSpacing: 1.8
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: WeatherState.aqi_band(root.aqi).label.toUpperCase()
                    color: WeatherState.aqi_color(root.aqi)
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-2)
                    font.letterSpacing: 1
                }

                // One cell per 10 AQI, lit up to the current value in its band's colour.
                Row {
                    id: gauge
                    Layout.fillWidth: true
                    Layout.preferredHeight: 8
                    spacing: 2
                    readonly property int cells: 30
                    readonly property real cell_w: (gauge.width - (gauge.cells - 1) * gauge.spacing) / gauge.cells

                    Repeater {
                        model: gauge.cells

                        Rectangle {
                            required property int index
                            readonly property bool lit: index * 10 < root.aqi
                            width: gauge.cell_w
                            height: gauge.height
                            color: lit ? WeatherState.aqi_color(index * 10) : Qt.alpha(root.visor, 0.12)
                        }
                    }
                }
            }
        }

        // Analysed compounds: the bar fills toward twice the unhealthy limit and turns to the warning colour once it crosses it.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            Repeater {
                model: root.compounds

                Item {
                    id: compound
                    required property var modelData
                    readonly property var value: root.cur ? root.cur[compound.modelData.key] : null
                    readonly property bool has_value: compound.value !== null && compound.value !== undefined
                    readonly property bool over: compound.has_value && compound.value >= compound.modelData.limit
                    readonly property real fill: compound.has_value ? Math.min(1, compound.value / (compound.modelData.limit * 2)) : 0
                    readonly property color tone: compound.over ? root.warning : root.visor_light

                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(name_text.implicitHeight, value_text.implicitHeight) + 2

                    Text {
                        id: name_text
                        width: Style.px(50)
                        anchors.verticalCenter: parent.verticalCenter
                        text: compound.modelData.name
                        color: compound.tone
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-3)
                        font.letterSpacing: 1
                    }

                    Text {
                        id: note_text
                        anchors.left: name_text.right
                        anchors.right: scan_bar.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.width >= 340
                        elide: Text.ElideRight
                        text: compound.modelData.note
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-5)
                        font.letterSpacing: 1.2
                    }

                    Rectangle {
                        id: scan_bar
                        anchors.right: value_text.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(60, root.width * 0.34)
                        height: 6
                        color: Qt.alpha(root.visor, 0.12)

                        Rectangle {
                            width: parent.width * compound.fill
                            height: parent.height
                            color: compound.tone
                            opacity: 0.9
                        }

                        // The unhealthy limit sits at the middle of the scale.
                        Rectangle {
                            x: parent.width / 2
                            y: -2
                            width: 1
                            height: parent.height + 4
                            color: Style.text_muted
                        }
                    }

                    Text {
                        id: value_text
                        width: Style.px(58)
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: compound.has_value ? compound.value.toFixed(1) : "--"
                        color: compound.over ? root.warning : Style.pal.fg_strong
                        font.family: Style.number_font
                        font.pixelSize: Style.fs(-2)
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            readonly property var r: root.cursor_row
            text: r ? "SCAN DATA · " + WeatherState.format_hour(new Date(r.dt)).toUpperCase() + " · AQI " + r.aqi + " · " + WeatherState.aqi_band(r.aqi).label.toUpperCase() : ""
            color: r ? WeatherState.aqi_color(r.aqi) : Style.text_muted
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
            font.letterSpacing: 1.2
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 60
            color: Qt.alpha(root.visor, 0.03)
            border.width: 1
            border.color: Qt.alpha(root.visor, 0.28)

            Canvas {
                id: canvas
                anchors.fill: parent
                anchors.margins: 5

                readonly property real col_w: canvas.width / Math.max(1, root.slice.length)

                function x_of(i) {
                    return (i + 0.5) * canvas.col_w;
                }

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                Connections {
                    target: WeatherState
                    function onAq_hoursChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: Style
                    function onPalChanged() { canvas.requestPaint(); }
                    function onFont_familyChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: TimeFormat
                    function onH24Changed() { canvas.requestPaint(); }
                }
                Connections {
                    target: Theme
                    function onTheme_labelChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: root
                    function onCursor_indexChanged() { canvas.requestPaint(); }
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const w = width, h = height;
                    const rows = root.slice;
                    if (rows.length === 0) return;

                    // Hex lattice, one hex per hour column.
                    const pitch = canvas.col_w;
                    const r = pitch / Math.sqrt(3);
                    const row_h = r * 1.5;
                    ctx.strokeStyle = root.visor;
                    ctx.globalAlpha = 0.09;
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    for (let j = 0; j * row_h < h + r; j++) {
                        const cy = j * row_h;
                        const shift = j % 2 === 1 ? pitch / 2 : 0;
                        for (let cx = shift; cx < w + pitch; cx += pitch) {
                            ctx.moveTo(cx - pitch / 2, cy - r / 2);
                            ctx.lineTo(cx, cy - r);
                            ctx.lineTo(cx + pitch / 2, cy - r / 2);
                            ctx.moveTo(cx - pitch / 2, cy - r / 2);
                            ctx.lineTo(cx - pitch / 2, cy + r / 2);
                        }
                    }
                    ctx.stroke();
                    ctx.globalAlpha = 1;

                    // Band thresholds as dashed contamination lines.
                    ctx.font = Style.fs(-5) + "px \"" + Style.font_family + "\"";
                    ctx.textAlign = "left";
                    ctx.lineWidth = 1;
                    for (const limit of [50, 100, 150]) {
                        if (limit > root.trace_max) continue;
                        const y = Math.round(root.trace_y(limit, h)) + 0.5;
                        ctx.strokeStyle = limit >= 150 ? root.warning : root.visor_light;
                        ctx.fillStyle = ctx.strokeStyle;
                        ctx.globalAlpha = 0.4;
                        ctx.setLineDash([2, 3]);
                        ctx.beginPath();
                        ctx.moveTo(0, y);
                        ctx.lineTo(w, y);
                        ctx.stroke();
                        ctx.setLineDash([]);
                        ctx.globalAlpha = 0.8;
                        ctx.fillText(String(limit), 2, y - 2);
                    }
                    ctx.globalAlpha = 1;

                    const base_y = h - root.trace_bottom;
                    ctx.strokeStyle = root.visor_light;
                    ctx.globalAlpha = 0.5;
                    ctx.beginPath();
                    ctx.moveTo(0, base_y + 0.5);
                    ctx.lineTo(w, base_y + 0.5);
                    ctx.stroke();

                    // Hour labels, thinned until they fit.
                    ctx.textAlign = "center";
                    const label_w = ctx.measureText(WeatherState.format_hour(new Date(2000, 0, 1, 12))).width + 8;
                    const clamp_x = x => Math.max(label_w / 2, Math.min(w - label_w / 2, x));
                    const step = [2, 3, 4, 6, 8, 12].find(n => n * canvas.col_w >= label_w) || 12;
                    for (let i = 0; i < rows.length; i++) {
                        const x = Math.round(canvas.x_of(i)) + 0.5;
                        const labelled = i % step === 0;
                        ctx.globalAlpha = labelled ? 0.55 : 0.25;
                        ctx.beginPath();
                        ctx.moveTo(x, base_y);
                        ctx.lineTo(x, base_y - (labelled ? 6 : 3));
                        ctx.stroke();
                        if (labelled && (i === root.cursor_index || Math.abs(clamp_x(canvas.x_of(i)) - clamp_x(canvas.x_of(root.cursor_index))) >= label_w + 4)) {
                            ctx.globalAlpha = 1;
                            ctx.fillStyle = i === root.cursor_index ? Style.pal.fg_strong : Style.text_muted;
                            ctx.fillText(WeatherState.format_hour(new Date(rows[i].dt)), clamp_x(canvas.x_of(i)), h - 4);
                        }
                    }
                    ctx.globalAlpha = 1;

                                    // The cursor hour's label is always shown; labels it would crowd are dropped.
                    if (root.cursor_index % step !== 0) {
                        ctx.fillStyle = Style.pal.fg_strong;
                        ctx.fillText(WeatherState.format_hour(new Date(rows[root.cursor_index].dt)), clamp_x(canvas.x_of(root.cursor_index)), h - 4);
                    }

                    // Glow: the trace wide and faint, then thin and bright.
                    ctx.strokeStyle = root.visor_light;
                    ctx.lineJoin = "round";
                    for (const pass of [[7, 0.1], [4, 0.2], [1.3, 1]]) {
                        ctx.lineWidth = pass[0];
                        ctx.globalAlpha = pass[1];
                        ctx.beginPath();
                        for (let i = 0; i < rows.length; i++) {
                            if (i === 0) ctx.moveTo(canvas.x_of(i), root.trace_y(rows[i].aqi, h)); else ctx.lineTo(canvas.x_of(i), root.trace_y(rows[i].aqi, h));
                        }
                        ctx.stroke();
                    }
                    ctx.globalAlpha = 1;

                    // Sample diamonds take their band's colour.
                    for (let i = 0; i < rows.length; i++) {
                        const x = canvas.x_of(i), y = root.trace_y(rows[i].aqi, h);
                        ctx.fillStyle = WeatherState.aqi_color(rows[i].aqi);
                        ctx.beginPath();
                        ctx.moveTo(x, y - 3);
                        ctx.lineTo(x + 3, y);
                        ctx.lineTo(x, y + 3);
                        ctx.lineTo(x - 3, y);
                        ctx.closePath();
                        ctx.fill();
                    }
                }

                // The lock follows the cursor: each selection builds a fresh one, so the brackets close in every time.
                Repeater {
                    model: root.slice.length

                    Loader {
                        required property int index
                        readonly property real lock_w: Math.max(canvas.col_w, 18)
                        active: index === root.cursor_index
                        x: canvas.x_of(index) - lock_w / 2
                        width: lock_w
                        height: canvas.height - root.trace_bottom + 4

                        sourceComponent: Item {
                            anchors.fill: parent

                            ScanLock {
                                shown: root.shown
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Qt.alpha(root.visor, 0.07)
                            }

                            Reticle {
                                readonly property real y_center: root.cursor_row ? root.trace_y(root.cursor_row.aqi, canvas.height) : 0
                                width: 22
                                height: 22
                                x: (parent.width - width) / 2
                                y: y_center - height / 2
                                color: root.visor_light
                                center_color: root.visor_light

                                NumberAnimation on rotation {
                                    running: root.shown
                                    loops: Animation.Infinite
                                    from: 0
                                    to: 360
                                    duration: 9000
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mouse => {
                        if (root.slice.length === 0) return;
                        root.on_select(Math.max(0, Math.min(root.slice.length - 1, Math.floor(mouse.x / canvas.col_w))));
                    }
                }
            }

            CornerBrackets {
                anchors.fill: parent
                color: Qt.alpha(root.visor, 0.75)
                inset: 0
                arm: 10
                thickness: 1.5
                all_corners: true
            }
        }
    }
}
