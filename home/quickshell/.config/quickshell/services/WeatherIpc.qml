import Quickshell.Io

IpcHandler {
    target: "weather"

    // Overlays a named fixture (services/WeatherFixture.js) on the live weather until "off" or a restart.
    function preview(name: string): string {
        if (name === "off") {
            WeatherState.preview_off();
            return "off";
        }
        return WeatherState.preview_set(name, false) ? "ok" : "unknown or no data yet; names: " + WeatherState.fixture_names.join(", ");
    }

    function previewing(): string {
        return WeatherState.preview_name;
    }
}
