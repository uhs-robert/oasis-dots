import QtQuick

// Accumulates fractional wheel deltas into whole 120-unit notches and
// snaps a percentage to the next multiple of 5 in a given direction.
QtObject {
    id: root

    property real accumulated: 0

    function consume(delta) {
        if (!delta) return 0;
        if ((delta > 0 && root.accumulated < 0) || (delta < 0 && root.accumulated > 0)) root.accumulated = 0;
        root.accumulated += delta;
        let notches = 0;
        while (Math.abs(root.accumulated) >= 120) {
            notches += root.accumulated > 0 ? 1 : -1;
            root.accumulated += root.accumulated > 0 ? -120 : 120;
        }
        return notches;
    }

    // Touchpads send pixel deltas; about 60px of swipe makes one notch.
    function consume_event(wheel) {
        return root.consume(wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y * 2 : wheel.angleDelta.y);
    }

    // Steps a level under the pointer by one snap step per notch and returns the new level (`current` until a notch
    // completes). `target` names what the wheel is over, so a partial notch left on one slider never moves the next;
    // a stepper that drives a single level passes null.
    property var level_target: null
    function step_level(wheel, target, current, min, max) {
        if (target !== root.level_target) {
            root.accumulated = 0;
            root.level_target = target;
        }
        const notches = root.consume_event(wheel);
        return notches === 0 ? current : root.snap_by(current, notches, min, max);
    }

    function snap(current, direction, min, max) {
        const step = 5;
        const target = direction > 0
            ? Math.floor(current / step) * step + step
            : Math.ceil(current / step) * step - step;
        return Math.max(min, Math.min(max, target));
    }

    // Applies `notches` snap steps in one direction starting from `current`.
    function snap_by(current, notches, min, max) {
        const direction = notches > 0 ? 1 : -1;
        let value = current;
        for (let i = 0; i < Math.abs(notches); i++) value = root.snap(value, direction, min, max);
        return value;
    }
}
