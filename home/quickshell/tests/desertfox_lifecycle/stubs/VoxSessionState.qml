pragma Singleton
import QtQuick
import Quickshell

// Stands in for features/voice/VoxSessionState: only the stat parser DesertfoxState borrows, copied from it.
Singleton {
    function process_start_time(stat: string): string {
        const after_name = stat.slice(stat.lastIndexOf(")") + 1).trim().split(/\s+/);
        return after_name.length > 19 ? after_name[19] : "";
    }
}
