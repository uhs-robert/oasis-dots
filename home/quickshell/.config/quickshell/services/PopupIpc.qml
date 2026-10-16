import Quickshell.Io

IpcHandler {
    target: "popup"

    function open(name: string): void {
        Popups.open(name, undefined);
    }

    function close(): void {
        Popups.close();
    }

    function toggle(name: string): void {
        Popups.toggle(name, undefined);
    }

    // "popup" when the open popup on the focused monitor took the keyboard back, else "none".
    function focus(): string {
        return Popups.focus_open() ? "popup" : "none";
    }

    // "yes" when the open or opening popup holds the keyboard, "no" when none is open or it is hands-off.
    function keyboard(): string {
        return Popups.takes_keyboard ? "yes" : "no";
    }

    // "opening <name>" while it animates in, "open <name>" once it is fully drawn, "closing <name>" while it animates
    // out, then "closed" once no popup layer is mapped.
    function state(): string {
        if (Popups.open_name === "") return Popups.closing_name === "" ? "closed" : "closing " + Popups.closing_name;
        return (Popups.settled_name === Popups.open_name ? "open " : "opening ") + Popups.open_name;
    }
}
