import Quickshell
import Quickshell.Io

Scope {
    id: root

    // Kept off the IpcHandler, which exposes every property it has.
    required property Osd osd

    IpcHandler {
        target: "osd"

        // "opening <what>" while it slides in, "open <what>" once drawn, "closing <what>" while it slides out, then "closed";
        // <what> is volume, brightness or voxtype.
        function state(): string {
            if (!root.osd.wanted) return root.osd.visible ? "closing " + root.osd.shown_what : "closed";
            return (root.osd.settled ? "open " : "opening ") + root.osd.shown_what;
        }
    }
}
