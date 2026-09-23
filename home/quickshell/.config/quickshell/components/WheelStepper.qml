// home/quickshell/.config/quickshell/components/WheelStepper.qml
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
