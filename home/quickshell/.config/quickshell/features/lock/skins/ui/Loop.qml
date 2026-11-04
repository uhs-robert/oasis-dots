import QtQuick
import "Motion.js" as Motion

// A looping keyframe track on a MotionClock, for a skin's endless motion (see MotionClock for why not an Animation).
// Like an Animation it restarts from the top each time `running` turns true and holds its value once stopped;
// bind the target to `value`.
QtObject {
    id: loop

    property var clock: null
    property bool running: false
    // [[duration_ms, to, ease], ...]; see Motion.track.
    property var keys: []
    property real first: 0
    property real t0: 0
    property real held: 0

    readonly property real elapsed: loop.running && loop.clock ? Math.max(0, loop.clock.t - loop.t0) : loop.held
    readonly property real value: Motion.track(loop.elapsed * 1000, loop.keys, loop.first)

    function restart() {
        loop.held = 0;
        if (loop.clock) loop.t0 = loop.clock.t;
    }

    onRunningChanged: {
        if (loop.running) loop.restart();
        else if (loop.clock) loop.held = Math.max(0, loop.clock.t - loop.t0);
    }
    onClockChanged: loop.restart()
    Component.onCompleted: loop.restart()
}
