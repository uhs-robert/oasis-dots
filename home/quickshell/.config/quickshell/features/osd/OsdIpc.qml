import Quickshell.Io

IpcHandler {
    required property Osd osd

    target: "osd"

    // "opening <what>" while it slides in, "open <what>" once drawn, "closing <what>" while it slides out, then "closed";
    // <what> is volume, brightness or voxtype.
    function state(): string {
        if (!osd.wanted) return osd.visible ? "closing " + osd.shown_what : "closed";
        return (osd.settled ? "open " : "opening ") + osd.shown_what;
    }
}
