import Quickshell
import Quickshell.Io

Scope {
    id: root

    // Kept off the IpcHandler, which exposes every property it has.
    required property Overview overview

    IpcHandler {
        target: "overview"

        // Marks every window to save as a session; `target_name` is a saved session to replace, or empty for a new one.
        function save_session(target_name: string): string {
            root.overview.begin_save(target_name);
            return "ok";
        }

        function open(): string {
            root.overview.show_overview("", false);
            return "ok";
        }

        function close(): string {
            root.overview.hide_overview();
            return "ok";
        }

        function search(): string {
            root.overview.show_overview("search", false);
            return "ok";
        }

        function move_follow(): string {
            root.overview.show_overview("move", true);
            return "ok";
        }

        function move_silent(): string {
            root.overview.show_overview("move", false);
            return "ok";
        }

        function toggle(): string {
            if (root.overview.wanted) root.overview.hide_overview();
            else root.overview.show_overview("", false);
            return "ok";
        }

        // "open" or "closed", for voxcmd and the shadow skill's wait.
        function state(): string {
            return root.overview.wanted ? "open" : "closed";
        }

        // The one entry for voice: `verb` runs the function its key does, `args` is a space-separated list. Returns "ok" or "error: <why>".
        function act(verb: string, args: string): string {
            return root.overview.voice_act(verb, args);
        }
    }
}
