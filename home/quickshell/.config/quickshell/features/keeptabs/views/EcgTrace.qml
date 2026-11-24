import QtQuick

// A heart monitor trace of `beat_count` beats across its width, for the Resident Evil condition look (Condition.js).
// It scrolls by moving one wider, pre-drawn canvas a beat to the left and starting over, so a frame costs a
// translation and never a repaint. The owner gates `running` on visibility and mains power.
Item {
    id: trace

    property string beat: "idle"
    property color line_color: "white"
    property real line_width: 2
    property int beat_count: 3
    property int beat_ms: 0
    property bool running: false
    readonly property real beat_w: trace.width / trace.beat_count

    // One heartbeat as (x, y) pairs across a beat's width, y from -1 (top) to 1 (bottom); traced from the mockup.
    readonly property var beats: ({
        running: [[0, 0], [0.3, 0], [0.36, -0.25], [0.42, 0.1], [0.48, -1], [0.54, 0.55], [0.6, 0], [1, 0]],
        waiting: [[0, 0], [0.25, 0], [0.3, -0.4], [0.36, 0.3], [0.42, -0.7], [0.5, 0.5], [0.56, 0], [1, 0]],
        done: [[0, 0], [0.35, 0], [0.4, -0.3], [0.45, 0], [1, 0]],
        idle: [[0, 0], [1, 0]]
    })

    clip: true

    onBeat_wChanged: if (scroll.running) scroll.restart()

    Canvas {
        id: strip
        width: trace.width + trace.beat_w
        height: trace.height

        onWidthChanged: strip.requestPaint()
        onHeightChanged: strip.requestPaint()
        Connections {
            target: trace
            function onBeatChanged() { strip.requestPaint(); }
            function onLine_colorChanged() { strip.requestPaint(); }
        }

        onPaint: {
            const ctx = strip.getContext("2d");
            ctx.reset();
            const pts = trace.beats[trace.beat] || trace.beats.idle;
            const mid = strip.height / 2;
            const amp = mid - trace.line_width;
            ctx.strokeStyle = trace.line_color;
            ctx.lineWidth = trace.line_width;
            ctx.lineJoin = "round";
            ctx.beginPath();
            for (let r = 0; r <= trace.beat_count; r++) {
                for (const p of pts) {
                    const x = (r + p[0]) * trace.beat_w;
                    const y = mid + p[1] * amp;
                    if (r === 0 && p === pts[0]) ctx.moveTo(x, y);
                    else ctx.lineTo(x, y);
                }
            }
            ctx.stroke();
        }

        // A running animation keeps the `to` it started with, so it waits for a width (a picker card is laid out after
        // it is made) and restarts when the width changes.
        NumberAnimation on x {
            id: scroll
            running: trace.running && trace.beat_ms > 0 && trace.beat_w > 0
            from: 0
            to: -trace.beat_w
            duration: trace.beat_ms
            loops: Animation.Infinite
            onRunningChanged: if (!running) strip.x = 0
        }
    }
}
