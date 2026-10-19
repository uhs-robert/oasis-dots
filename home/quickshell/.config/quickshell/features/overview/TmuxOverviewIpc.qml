import Quickshell
import Quickshell.Io

Scope {
    id: root

    // Kept off the IpcHandler, which exposes every property it has.
    required property TmuxOverview tmux_overview

    IpcHandler {
        target: "tmux_overview"

        function open(): string {
            root.tmux_overview.show_overview();
            return "ok";
        }

        function close(): string {
            root.tmux_overview.hide_overview();
            return "ok";
        }

        function search(): string {
            root.tmux_overview.show_overview();
            root.tmux_overview.start_filter(true);
            return "ok";
        }

        function toggle(): string {
            if (root.tmux_overview.wanted) root.tmux_overview.hide_overview();
            else root.tmux_overview.show_overview();
            return "ok";
        }

        // "open" or "closed", for voxcmd.
        function state(): string {
            return root.tmux_overview.wanted ? "open" : "closed";
        }
    }
}
