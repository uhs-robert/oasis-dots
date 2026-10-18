import Quickshell.Io
import qs.services
import qs.features.popups

IpcHandler {
    target: "calendar"

    // Rereads the cache now, for calendar-sync to call after it writes.
    function refresh(): void {
        CalendarState.refresh();
    }

    // Opens the clock popup on a day, "YYYY-MM-DD".
    function open_day(date: string): string {
        if (!CalendarState.parse_day(date)) return "bad date, expected YYYY-MM-DD";
        CalendarState.requested_day = date;
        Popups.open("clock", undefined);
        return "ok";
    }
}
