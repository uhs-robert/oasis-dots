import QtQuick

// The lock's one source of continuous motion: seconds of running time, stepped about 60 times a second.
// An infinite Animation steps on every vsync, so a 240 Hz screen redraws the whole skin 240 times a second; a property
// set from this timer redraws each window once per step instead. Every screen shares the ctx's clock, because two
// timers out of phase would each trigger their own redraws.
QtObject {
    id: clock

    property bool running: false
    property real t: 0
    property double last_ms: 0

    // dt in seconds, for motion that accumulates (a stream that only moves while on).
    signal ticked(real dt)

    property Timer timer: Timer {
        interval: 16
        repeat: true
        running: clock.running
        onRunningChanged: clock.last_ms = Date.now()
        onTriggered: {
            const now = Date.now();
            // Capped so a suspend or a stalled frame does not jump everything forward.
            const dt = Math.min(0.1, Math.max(0, (now - clock.last_ms) / 1000));
            clock.last_ms = now;
            clock.t += dt;
            clock.ticked(dt);
        }
    }
}
