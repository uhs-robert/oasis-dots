// home/quickshell/.config/quickshell/services/WeatherState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"
import "Astro.js" as Astro

// One shared Open-Meteo fetch for every bar. Ported from the Waybar Ruby weather
// script (get_weather.rb) so the module has no Ruby dependency.
Singleton {
    id: root

    readonly property var default_settings: ({
        latitude: "auto",
        longitude: "auto",
        unit: "fahrenheit",
        time_format: "12h",
        days: 7
    })

    property var settings: default_settings

    property var current: null
    property var hours: []
    property var days: []
    property string location_name: ""
    property double updated: 0
    property string sunrise: ""
    property string sunset: ""
    property var moon: ({ phase: 0, name: "" })

    property bool has_data: false
    property bool loading: false
    property bool stale: false
    property string error: ""

    property double last_success_ms: 0
    property bool warned_once: false
    property double last_attempt_ms: 0
    property int utc_offset: 0
    property string fetch_key: ""
    property real lat: 0
    property real lon: 0

    property var aq_current: null
    property var aq_hours: []
    property bool aq_has_data: false
    property bool aq_loading: false
    property string aq_error: ""

    property var alerts: []
    property bool alerts_has_data: false
    property string alerts_error: ""

    readonly property int refresh_interval_ms: 900000
    readonly property int request_timeout_ms: 10000
    readonly property int min_refresh_gap_ms: 60000
    readonly property int retry_gap_ms: 120000

    property var base_settings: ({})
    property var local_settings: ({})

    function apply_settings() {
        const merged = Object.assign({}, root.default_settings, root.base_settings, root.local_settings);
        const changed = root.has_data && JSON.stringify(root.settings) !== JSON.stringify(merged);
        root.settings = merged;
        if (changed) root.refresh(true);
    }

    function parse_settings(file, name) {
        try {
            return JSON.parse(file.text());
        } catch (e) {
            console.warn("Weather: invalid " + name + " (" + e + ")");
            return null;
        }
    }

    FileView {
        id: settings_file
        path: Quickshell.shellDir + "/weather.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const parsed = root.parse_settings(settings_file, "weather.json");
            if (parsed) root.base_settings = parsed;
            root.apply_settings();
        }
        onLoadFailed: error => console.warn("Weather: failed to load weather.json (" + error + "), using defaults")
    }

    // Untracked per-machine overrides, e.g. real coordinates kept out of the public repo.
    FileView {
        id: local_settings_file
        path: Quickshell.shellDir + "/weather.local.json"
        printErrors: false
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const parsed = root.parse_settings(local_settings_file, "weather.local.json");
            if (parsed) root.local_settings = parsed;
            root.apply_settings();
        }
        onLoadFailed: error => {
            root.local_settings = {};
            root.apply_settings();
        }
    }

    readonly property string cache_dir: {
        const xdg = Quickshell.env("XDG_CACHE_HOME");
        const base = xdg && xdg !== "" ? xdg : (Quickshell.env("HOME") + "/.cache");
        return base + "/quickshell";
    }

    Process {
        id: ensure_cache_dir
        command: ["mkdir", "-p", root.cache_dir]
    }

    FileView {
        id: cache_file
        path: root.cache_dir + "/weather.json"
        blockLoading: true
        watchChanges: false
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (parsed.settings_key !== JSON.stringify(root.settings) || !parsed.current) return;
                root.apply_data(parsed);
                root.last_success_ms = parsed.updated || 0;
            } catch (e) {
                console.warn("Weather: invalid cache file (" + e + ")");
            }
        }
        onLoadFailed: error => {}
    }

    Component.onCompleted: {
        ensure_cache_dir.running = true;
        settings_file.reload();
        local_settings_file.reload();
        cache_file.reload();
        root.refresh_if_due();
    }

    // Checks every minute so the refresh follows the data's age, not process uptime.
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.refresh_if_due()
    }

    function refresh_if_due() {
        const now = Date.now();
        const day_rolled = root.days.length > 0 && root.days[0].date !== root.location_date_str();
        const due = day_rolled || now - root.last_success_ms >= root.refresh_interval_ms;
        if (due && now - root.last_attempt_ms >= root.retry_gap_ms) root.refresh(true);
    }

    // A non-forced call within min_refresh_gap_ms of the last success is a no-op.
    function refresh(force) {
        if (root.loading) return;
        const now = Date.now();
        if (!force && root.last_success_ms > 0 && (now - root.last_success_ms) < root.min_refresh_gap_ms) return;
        root.loading = true;
        root.last_attempt_ms = now;
        root.fetch_key = JSON.stringify(root.settings);
        root.start_fetch();
    }

    function start_fetch() {
        const lat = root.settings.latitude;
        const lon = root.settings.longitude;
        if (String(lat) === "auto" || String(lon) === "auto") {
            root.fetch_location();
        } else {
            root.fetch_forecast(root.parse_num(lat, 0), root.parse_num(lon, 0), "");
        }
    }

    function fetch_location() {
        const xhr = new XMLHttpRequest();
        xhr.timeout = root.request_timeout_ms;
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    const data = JSON.parse(xhr.responseText);
                    const name = [data.city, data.regionName, data.country].filter(p => !!p).join(", ");
                    root.fetch_forecast(root.parse_num(data.lat, 0), root.parse_num(data.lon, 0), name);
                } catch (e) {
                    root.fail("location parse error: " + e);
                }
            } else {
                root.fail("location request failed: " + xhr.status);
            }
        };
        xhr.onerror = () => root.fail("location request network error");
        xhr.ontimeout = () => root.fail("location request timed out");
        xhr.open("GET", "http://ip-api.com/json/?fields=lat,lon,city,regionName,country");
        xhr.send();
    }

    function fetch_forecast(lat, lon, location_name) {
        root.lat = lat;
        root.lon = lon;

        const unit_c = root.settings.unit === "celsius";
        const days_count = Math.max(1, Math.min(16, root.settings.days || 7));
        const params = {
            latitude: lat,
            longitude: lon,
            current: "temperature_2m,apparent_temperature,is_day,precipitation,weather_code,relative_humidity_2m,dew_point_2m,pressure_msl,visibility,uv_index,cloud_cover,wind_speed_10m,wind_direction_10m,wind_gusts_10m",
            hourly: "temperature_2m,precipitation_probability,precipitation,weather_code,is_day,apparent_temperature,relative_humidity_2m,uv_index,wind_speed_10m,wind_direction_10m,wind_gusts_10m,dew_point_2m,pressure_msl,visibility,cloud_cover",
            daily: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,sunrise,sunset,uv_index_max,wind_speed_10m_max,wind_gusts_10m_max,wind_direction_10m_dominant,sunshine_duration",
            temperature_unit: unit_c ? "celsius" : "fahrenheit",
            precipitation_unit: unit_c ? "mm" : "inch",
            wind_speed_unit: unit_c ? "kmh" : "mph",
            timezone: "auto",
            forecast_days: days_count
        };
        const query = Object.keys(params).map(k => encodeURIComponent(k) + "=" + encodeURIComponent(params[k])).join("&");

        const xhr = new XMLHttpRequest();
        xhr.timeout = root.request_timeout_ms;
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status !== 200) {
                root.fail("forecast request failed: " + xhr.status);
                return;
            }
            const body = xhr.responseText;
            if (!/^\s*[[{]/.test(body || "")) {
                root.fail("forecast response not JSON (status " + xhr.status + ", " + root.body_snippet(body) + ")");
                return;
            }
            try {
                root.handle_forecast(JSON.parse(body), location_name, lat, lon);
            } catch (e) {
                root.fail("forecast parse error: " + e + " (" + root.body_snippet(body) + ")");
            }
        };
        xhr.onerror = () => root.fail("forecast request network error");
        xhr.ontimeout = () => root.fail("forecast request timed out");
        xhr.open("GET", "https://api.open-meteo.com/v1/forecast?" + query);
        xhr.send();

        root.fetch_air_quality(lat, lon);
        root.fetch_alerts(lat, lon);
    }

    function handle_forecast(blob, location_name, lat, lon) {
        if (root.fetch_key !== JSON.stringify(root.settings)) {
            root.loading = false;
            root.refresh(true);
            return;
        }
        try {
            const parsed = root.parse_blob(blob, location_name, lat, lon);
            root.apply_data(parsed);
            root.last_success_ms = Date.now();
            root.loading = false;
            root.error = "";
            root.stale = false;
            root.warned_once = false;
            root.save_cache();
        } catch (e) {
            root.fail("parse error: " + e);
        }
    }

    // First bytes of a bad response body, for a one-line log without dumping the whole thing.
    function body_snippet(text) {
        if (!text) return "empty body";
        return "first bytes: " + JSON.stringify(text.trim().slice(0, 60));
    }

    function fail(msg) {
        root.loading = false;
        root.stale = root.has_data;
        root.error = msg;
        if (!root.warned_once) {
            console.warn("Weather: " + msg);
            root.warned_once = true;
        }
    }

    // Air quality is fetched separately: a failure here never marks the main forecast stale.
    function fetch_air_quality(lat, lon) {
        const key = root.fetch_key;
        root.aq_loading = true;
        const params = {
            latitude: lat,
            longitude: lon,
            current: "us_aqi,pm2_5,pm10,ozone",
            hourly: "us_aqi",
            forecast_days: 2,
            timezone: "auto"
        };
        const query = Object.keys(params).map(k => encodeURIComponent(k) + "=" + encodeURIComponent(params[k])).join("&");

        const xhr = new XMLHttpRequest();
        xhr.timeout = root.request_timeout_ms;
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || key !== root.fetch_key) return;
            root.aq_loading = false;
            if (xhr.status === 200) {
                try {
                    root.handle_air_quality(JSON.parse(xhr.responseText));
                } catch (e) {
                    root.aq_error = "air quality parse error: " + e;
                }
            } else {
                root.aq_error = "air quality request failed: " + xhr.status;
            }
        };
        xhr.onerror = () => { if (key === root.fetch_key) { root.aq_loading = false; root.aq_error = "air quality network error"; } };
        xhr.ontimeout = () => { if (key === root.fetch_key) { root.aq_loading = false; root.aq_error = "air quality request timed out"; } };
        xhr.open("GET", "https://air-quality-api.open-meteo.com/v1/air-quality?" + query);
        xhr.send();
    }

    function handle_air_quality(blob) {
        const cur = blob.current || {};
        root.aq_current = {
            aqi: Math.round(root.parse_num(cur.us_aqi, -1)),
            pm25: root.parse_num(cur.pm2_5, 0),
            pm10: root.parse_num(cur.pm10, 0),
            ozone: root.parse_num(cur.ozone, 0)
        };

        const hourly = blob.hourly || {};
        const times = hourly.time || [];
        const aqis = hourly.us_aqi || [];
        const now_local = new Date(cur.time || Date.now());
        const all = [];
        for (let i = 0; i < times.length; i++) {
            all.push({ dt: new Date(times[i]).toISOString(), aqi: Math.round(root.parse_num(aqis[i], 0)) });
        }
        let next = all.filter(h => new Date(h.dt) >= now_local);
        if (next.length === 0 && all.length > 0) next = all;
        root.aq_hours = next.slice(0, 24);
        root.aq_has_data = true;
        root.aq_error = "";
        root.save_cache();
    }

    // US National Weather Service active alerts for this point. A failure or a non-US
    // location (404/empty) just means no alerts; it never marks the forecast stale.
    function fetch_alerts(lat, lon) {
        const key = root.fetch_key;
        const xhr = new XMLHttpRequest();
        xhr.timeout = root.request_timeout_ms;
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || key !== root.fetch_key) return;
            if (xhr.status === 200) {
                try {
                    root.handle_alerts(JSON.parse(xhr.responseText));
                } catch (e) {
                    root.alerts_error = "alerts parse error: " + e;
                }
            } else {
                root.alerts = [];
                root.alerts_has_data = true;
                root.alerts_error = "";
            }
        };
        xhr.onerror = () => { if (key === root.fetch_key) { root.alerts = []; root.alerts_has_data = true; } };
        xhr.ontimeout = () => { if (key === root.fetch_key) { root.alerts = []; root.alerts_has_data = true; } };
        xhr.open("GET", "https://api.weather.gov/alerts/active?point=" + lat.toFixed(4) + "," + lon.toFixed(4));
        try {
            xhr.setRequestHeader("User-Agent", "quickshell-weather (dotfiles)");
            xhr.setRequestHeader("Accept", "application/geo+json");
        } catch (e) {
            console.warn("Weather: could not set alert request headers (" + e + ")");
        }
        xhr.send();
    }

    readonly property var alert_severity_rank: ({ Extreme: 0, Severe: 1, Moderate: 2, Minor: 3, Unknown: 4 })

    function handle_alerts(geojson) {
        const features = geojson.features || [];
        const now = Date.now();
        const list = [];
        for (const f of features) {
            const p = f.properties || {};
            const ends = p.ends || p.expires || "";
            if (ends && new Date(ends).getTime() < now) continue;
            list.push({
                event: p.event || "Alert",
                severity: p.severity || "Unknown",
                urgency: p.urgency || "Unknown",
                headline: p.headline || "",
                description: p.description || "",
                instruction: p.instruction || "",
                onset: p.onset || p.effective || "",
                ends: ends,
                area: p.areaDesc || "",
                sender: p.senderName || ""
            });
        }
        list.sort((a, b) => {
            const ra = root.alert_severity_rank[a.severity] !== undefined ? root.alert_severity_rank[a.severity] : 4;
            const rb = root.alert_severity_rank[b.severity] !== undefined ? root.alert_severity_rank[b.severity] : 4;
            if (ra !== rb) return ra - rb;
            return new Date(a.onset) - new Date(b.onset);
        });
        root.alerts = list;
        root.alerts_has_data = true;
        root.alerts_error = "";
        root.save_cache();
    }

    function alert_color(severity) {
        if (severity === "Extreme" || severity === "Severe") return Theme.error;
        if (severity === "Moderate") return Theme.warning;
        if (severity === "Minor") return Theme.yellow;
        return Theme.info;
    }

    function apply_data(parsed) {
        root.current = parsed.current;
        root.hours = parsed.hours;
        root.days = parsed.days;
        root.location_name = parsed.location_name;
        root.updated = parsed.updated;
        root.sunrise = parsed.sunrise;
        root.sunset = parsed.sunset;
        root.moon = parsed.moon;
        root.utc_offset = parsed.utc_offset || 0;
        root.lat = parsed.lat || root.lat;
        root.lon = parsed.lon || root.lon;
        if (parsed.aq_current !== undefined) root.aq_current = parsed.aq_current;
        if (parsed.aq_hours !== undefined) root.aq_hours = parsed.aq_hours;
        if (parsed.aq_current) root.aq_has_data = true;
        if (parsed.alerts !== undefined) {
            root.alerts = parsed.alerts;
            root.alerts_has_data = true;
        }
        root.has_data = true;
    }

    // Persists the whole shared state in one file so a restart shows data immediately.
    function save_cache() {
        if (!root.current) return;
        const snapshot = {
            current: root.current,
            hours: root.hours,
            days: root.days,
            location_name: root.location_name,
            updated: root.updated,
            sunrise: root.sunrise,
            sunset: root.sunset,
            moon: root.moon,
            utc_offset: root.utc_offset,
            lat: root.lat,
            lon: root.lon,
            aq_current: root.aq_current,
            aq_hours: root.aq_hours,
            alerts: root.alerts,
            settings_key: JSON.stringify(root.settings)
        };
        cache_file.setText(JSON.stringify(snapshot));
    }

    // Wall-clock time at the forecast location; read it with the getUTC* methods.
    function location_now() {
        return new Date(Date.now() + root.utc_offset * 1000);
    }

    function location_date_str() {
        return root.location_now().toISOString().substr(0, 10);
    }

    function parse_num(val, def) {
        const n = parseFloat(val);
        return isNaN(n) ? def : n;
    }

    function fmt_time(iso) {
        if (!iso) return "";
        const idx = iso.indexOf("T");
        return idx === -1 ? "" : iso.substr(idx + 1, 5);
    }

    // `current` doesn't reliably carry every field on every Open-Meteo revision; the
    // hourly entry nearest to now is a robust fallback source for all of them.
    function current_hour_index(hourly, now_local) {
        for (let i = 0; i < hourly.time.length; i++) {
            if (new Date(hourly.time[i]) >= now_local) return i;
        }
        return 0;
    }

    function pick(cur_val, hourly_arr, idx, def) {
        if (cur_val !== undefined && cur_val !== null) return root.parse_num(cur_val, def);
        return hourly_arr ? root.parse_num(hourly_arr[idx], def) : def;
    }

    function parse_blob(blob, location_name, lat, lon) {
        const cur = blob.current;
        const hourly = blob.hourly;
        const daily = blob.daily;
        const now_local = new Date(cur.time);
        const now_idx = root.current_hour_index(hourly, now_local);

        const current = {
            temp: root.parse_num(cur.temperature_2m, 0),
            feels: root.parse_num(cur.apparent_temperature, 0),
            code: Math.round(root.parse_num(cur.weather_code, 0)),
            is_day: cur.is_day ? 1 : 0,
            precip: root.parse_num(cur.precipitation, 0),
            cond: root.description(cur.weather_code),
            humidity: Math.round(root.pick(cur.relative_humidity_2m, hourly.relative_humidity_2m, now_idx, 0)),
            dew_point: root.pick(cur.dew_point_2m, hourly.dew_point_2m, now_idx, 0),
            pressure: root.pick(cur.pressure_msl, hourly.pressure_msl, now_idx, 0),
            visibility: root.pick(cur.visibility, hourly.visibility, now_idx, 0),
            uv_index: root.pick(cur.uv_index, hourly.uv_index, now_idx, 0),
            cloud_cover: Math.round(root.pick(cur.cloud_cover, hourly.cloud_cover, now_idx, 0)),
            wind_speed: root.pick(cur.wind_speed_10m, hourly.wind_speed_10m, now_idx, 0),
            wind_dir: Math.round(root.pick(cur.wind_direction_10m, hourly.wind_direction_10m, now_idx, 0)),
            wind_gusts: root.pick(cur.wind_gusts_10m, hourly.wind_gusts_10m, now_idx, 0)
        };

        // Every remaining hour across every fetched day (the Hourly popup tab scrolls the whole range).
        const all_hours = [];
        for (let i = 0; i < hourly.time.length; i++) {
            const dt = new Date(hourly.time[i]);
            all_hours.push({
                dt: dt.toISOString(),
                date: Qt.formatDate(dt, "yyyy-MM-dd"),
                hour: dt.getHours(),
                temp: root.parse_num(hourly.temperature_2m[i], 0),
                feels: root.parse_num(hourly.apparent_temperature ? hourly.apparent_temperature[i] : undefined, 0),
                pop: Math.round(root.parse_num(hourly.precipitation_probability[i], 0)),
                precip: root.parse_num(hourly.precipitation[i], 0),
                code: Math.round(root.parse_num(hourly.weather_code[i], 0)),
                is_day: hourly.is_day[i] ? 1 : 0,
                cond: root.description(hourly.weather_code[i]),
                humidity: Math.round(root.parse_num(hourly.relative_humidity_2m ? hourly.relative_humidity_2m[i] : undefined, 0)),
                uv_index: root.parse_num(hourly.uv_index ? hourly.uv_index[i] : undefined, 0),
                wind_speed: root.parse_num(hourly.wind_speed_10m ? hourly.wind_speed_10m[i] : undefined, 0),
                wind_dir: Math.round(root.parse_num(hourly.wind_direction_10m ? hourly.wind_direction_10m[i] : undefined, 0)),
                wind_gusts: root.parse_num(hourly.wind_gusts_10m ? hourly.wind_gusts_10m[i] : undefined, 0)
            });
        }
        let next_hours = all_hours.filter(h => new Date(h.dt) >= now_local);
        if (next_hours.length === 0 && all_hours.length > 0) next_hours = all_hours;

        const day_limit = Math.max(1, Math.min(16, root.settings.days || 7));
        const days = [];
        for (let i = 0; i < Math.min(day_limit, daily.time.length); i++) {
            const date_str = daily.time[i];
            const d = new Date(date_str + "T00:00:00");
            days.push({
                date: date_str,
                weekday: i === 0 ? "Today" : Qt.formatDate(d, "ddd"),
                min: root.parse_num(daily.temperature_2m_min[i], 0),
                max: root.parse_num(daily.temperature_2m_max[i], 0),
                code: Math.round(root.parse_num(daily.weather_code[i], 0)),
                cond: root.description(daily.weather_code[i]),
                pop: Math.round(root.parse_num(daily.precipitation_probability_max[i], 0)),
                precip: root.parse_num(daily.precipitation_sum[i], 0),
                sunrise: root.fmt_time(daily.sunrise[i]),
                sunset: root.fmt_time(daily.sunset[i]),
                uv_max: root.parse_num(daily.uv_index_max ? daily.uv_index_max[i] : undefined, 0),
                wind_speed_max: root.parse_num(daily.wind_speed_10m_max ? daily.wind_speed_10m_max[i] : undefined, 0),
                wind_gusts_max: root.parse_num(daily.wind_gusts_10m_max ? daily.wind_gusts_10m_max[i] : undefined, 0),
                wind_dir: Math.round(root.parse_num(daily.wind_direction_10m_dominant ? daily.wind_direction_10m_dominant[i] : undefined, 0)),
                sunshine_hours: root.parse_num(daily.sunshine_duration ? daily.sunshine_duration[i] : undefined, 0) / 3600
            });
        }

        const today = days.length > 0 ? days[0] : null;
        const phase = root.moon_phase(new Date());

        return {
            current: current,
            hours: next_hours,
            days: days,
            location_name: location_name || blob.timezone || "",
            updated: Date.now(),
            sunrise: today ? today.sunrise : "",
            sunset: today ? today.sunset : "",
            moon: { phase: phase, name: root.moon_name(phase) },
            utc_offset: blob.utc_offset_seconds || 0,
            lat: lat,
            lon: lon,
            settings_key: JSON.stringify(root.settings)
        };
    }

    // --- Moon phase (ported from MoonPhase.calculate_phase / phase_name) ---

    readonly property double known_new_moon_ms: Date.UTC(2000, 0, 6, 18, 14, 0)
    readonly property double lunar_cycle_days: 29.530588861

    function moon_phase(date) {
        const days_since = (date.getTime() - root.known_new_moon_ms) / 86400000.0;
        let phase = (days_since % root.lunar_cycle_days) / root.lunar_cycle_days;
        phase = phase % 1.0;
        return phase < 0 ? phase + 1.0 : phase;
    }

    function moon_name(phase) {
        if (phase < 0.0625 || phase >= 0.9375) return "New Moon";
        if (phase < 0.1875) return "Waxing Crescent";
        if (phase < 0.3125) return "First Quarter";
        if (phase < 0.4375) return "Waxing Gibbous";
        if (phase < 0.5625) return "Full Moon";
        if (phase < 0.6875) return "Waning Gibbous";
        if (phase < 0.8125) return "Last Quarter";
        return "Waning Crescent";
    }

    // Location-clock midnight (as a UTC instant) for a "YYYY-MM-DD" date at this forecast location.
    function local_midnight_ms(date_str) {
        return Date.parse(date_str + "T00:00:00Z") - root.utc_offset * 1000;
    }

    readonly property var month_names: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    // "until 6:00 AM", with the weekday when the end falls on another day at the location.
    function fmt_until(iso) {
        if (!iso) return "";
        const d = new Date(iso);
        const shifted = new Date(d.getTime() + root.utc_offset * 1000);
        const day = shifted.toISOString().substr(0, 10) === root.location_date_str() ? "" : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][shifted.getUTCDay()] + " ";
        return "until " + day + root.fmt_location_time(d);
    }

    // Formats a UTC instant as "H:MMam" (or 24h "HH:MM") in the forecast location's clock.
    function fmt_location_time(date) {
        if (!date) return null;
        const shifted = new Date(date.getTime() + root.utc_offset * 1000);
        const h = shifted.getUTCHours(), m = shifted.getUTCMinutes();
        const mm = m < 10 ? "0" + m : "" + m;
        if (root.settings.time_format === "12h") {
            let hh = h % 12;
            if (hh === 0) hh = 12;
            return hh + ":" + mm + (h < 12 ? "am" : "pm");
        }
        return (h < 10 ? "0" + h : "" + h) + ":" + mm;
    }

    function moon_times_for_date(date_str) {
        if (!date_str || (root.lat === 0 && root.lon === 0)) return { rise: null, set: null, always_up: false, always_down: false };
        const t0 = root.local_midnight_ms(date_str);
        const result = Astro.moon_times(new Date(t0), root.lat, root.lon);
        return {
            rise: result.rise ? root.fmt_location_time(result.rise) : null,
            set: result.set ? root.fmt_location_time(result.set) : null,
            always_up: !!result.alwaysUp,
            always_down: !!result.alwaysDown
        };
    }

    function moon_phase_for_date(date_str) {
        const t0 = root.local_midnight_ms(date_str);
        return root.moon_phase(new Date(t0 + 12 * 3600000));
    }

    // Closed form: phase advances at a constant rate, so the next full moon is one calculation away.
    function next_full_moon_label(date_str) {
        const t0 = root.local_midnight_ms(date_str);
        const phase = root.moon_phase_for_date(date_str);
        const frac = ((0.5 - phase) % 1 + 1) % 1;
        const days_ahead = frac * root.lunar_cycle_days;
        const target = new Date(t0 + 12 * 3600000 + days_ahead * 86400000);
        const shifted = new Date(target.getTime() + root.utc_offset * 1000);
        return root.month_names[shifted.getUTCMonth()] + " " + shifted.getUTCDate();
    }

    readonly property var moon_icon_slugs: ({
        new: "moon-new",
        waxing_crescent: "moon-waxing-crescent",
        first_quarter: "moon-first-quarter",
        waxing_gibbous: "moon-waxing-gibbous",
        full: "moon-full",
        waning_gibbous: "moon-waning-gibbous",
        last_quarter: "moon-last-quarter",
        waning_crescent: "moon-waning-crescent"
    })

    function moon_phase_key(phase) {
        if (phase < 0.0625 || phase >= 0.9375) return "new";
        if (phase < 0.1875) return "waxing_crescent";
        if (phase < 0.3125) return "first_quarter";
        if (phase < 0.4375) return "waxing_gibbous";
        if (phase < 0.5625) return "full";
        if (phase < 0.6875) return "waning_gibbous";
        if (phase < 0.8125) return "last_quarter";
        return "waning_crescent";
    }

    function asset_url(slug) {
        return Qt.resolvedUrl("../assets/weather/" + slug + ".svg");
    }

    function moon_icon_source(phase) {
        return root.asset_url(root.moon_icon_slugs[root.moon_phase_key(phase)]);
    }

    readonly property string sun_rise_icon: root.asset_url("sunrise")
    readonly property string sun_set_icon: root.asset_url("sunset")
    readonly property string raindrop_icon: root.asset_url("raindrop")

    // --- WMO condition codes, mapped to vendored Meteocons fill-style SVGs ---
    // (assets/weather/, from @meteocons/svg-static, MIT license)

    readonly property var weather_icon_map: ({
        0: { day: "clear-day", night: "clear-night", desc: "Clear sky" },
        1: { day: "mostly-clear-day", night: "mostly-clear-night", desc: "Mainly clear" },
        2: { day: "partly-cloudy-day", night: "partly-cloudy-night", desc: "Partly cloudy" },
        3: { day: "overcast-day", night: "overcast-night", desc: "Overcast" },
        45: { day: "fog-day", night: "fog-night", desc: "Fog" },
        48: { day: "fog-day", night: "fog-night", desc: "Depositing rime fog" },
        51: { day: "drizzle", night: "drizzle", desc: "Light drizzle" },
        53: { day: "drizzle", night: "drizzle", desc: "Moderate drizzle" },
        55: { day: "overcast-drizzle", night: "overcast-drizzle", desc: "Dense drizzle" },
        56: { day: "sleet", night: "sleet", desc: "Light freezing drizzle" },
        57: { day: "sleet", night: "sleet", desc: "Dense freezing drizzle" },
        61: { day: "rain", night: "rain", desc: "Slight rain" },
        63: { day: "overcast-rain", night: "overcast-rain", desc: "Moderate rain" },
        65: { day: "extreme-rain", night: "extreme-rain", desc: "Heavy rain" },
        66: { day: "sleet", night: "sleet", desc: "Light freezing rain" },
        67: { day: "extreme-sleet", night: "extreme-sleet", desc: "Heavy freezing rain" },
        71: { day: "snow", night: "snow", desc: "Slight snow fall" },
        73: { day: "overcast-snow", night: "overcast-snow", desc: "Moderate snow fall" },
        75: { day: "extreme-snow", night: "extreme-snow", desc: "Heavy snow fall" },
        77: { day: "snow", night: "snow", desc: "Snow grains" },
        80: { day: "rain", night: "rain", desc: "Slight rain showers" },
        81: { day: "overcast-rain", night: "overcast-rain", desc: "Moderate rain showers" },
        82: { day: "extreme-rain", night: "extreme-rain", desc: "Violent rain showers" },
        85: { day: "snow", night: "snow", desc: "Slight snow showers" },
        86: { day: "extreme-snow", night: "extreme-snow", desc: "Heavy snow showers" },
        95: { day: "thunderstorms", night: "thunderstorms", desc: "Thunderstorm" },
        96: { day: "thunderstorms-hail", night: "thunderstorms-hail", desc: "Thunderstorm with slight hail" },
        99: { day: "extreme-thunderstorms-hail", night: "extreme-thunderstorms-hail", desc: "Thunderstorm with heavy hail" }
    })

    readonly property var weather_color_keys: ({
        0: "clear", 1: "clear", 2: "partly_cloudy", 3: "overcast",
        45: "fog", 48: "fog",
        51: "drizzle", 53: "drizzle", 55: "drizzle", 56: "freezing_rain", 57: "freezing_rain",
        61: "rain", 63: "rain", 65: "heavy_rain", 66: "freezing_rain", 67: "freezing_rain",
        71: "snow", 73: "snow", 75: "heavy_snow", 77: "heavy_snow",
        80: "rain", 81: "rain", 82: "heavy_rain", 85: "snow", 86: "heavy_snow",
        95: "thunderstorm", 96: "thunderstorm", 99: "thunderstorm"
    })

    function icon_source(code, is_day) {
        const entry = root.weather_icon_map[Math.round(code)];
        if (!entry) return root.asset_url("not-available");
        return root.asset_url(is_day ? entry.day : (entry.night || entry.day));
    }

    function description(code) {
        const entry = root.weather_icon_map[Math.round(code)];
        return entry ? entry.desc : "Unknown";
    }

    function condition_color(code, is_day) {
        const key = root.weather_color_keys[Math.round(code)] || "clear";
        switch (key) {
        case "clear": return is_day ? Theme.yellow : Theme.magenta;
        case "partly_cloudy": return is_day ? Theme.bright_yellow : Theme.bright_magenta;
        case "overcast": return Theme.fg_dim;
        case "fog": return Theme.fg_dim;
        case "drizzle": return Theme.cyan;
        case "rain": return Theme.blue;
        case "heavy_rain": return Theme.bright_blue;
        case "freezing_rain": return Theme.bright_cyan;
        case "snow": return Theme.cyan;
        case "heavy_snow": return Theme.bright_cyan;
        case "thunderstorm": return Theme.yellow;
        default: return Theme.theme_primary;
        }
    }

    // --- Temperature and precipitation bands (ported from Temperature / Precipitation) ---

    function temp_color(temp) {
        const unit_c = root.settings.unit === "celsius";
        const very_cold = unit_c ? 5 : 41;
        const cold = unit_c ? 18 : 65;
        const chilly = unit_c ? 19 : 66;
        const neutral = unit_c ? 24 : 76;
        const warm = unit_c ? 29 : 85;
        if (temp < very_cold) return Theme.bright_cyan;
        if (temp < cold) return Theme.cyan;
        if (temp < chilly) return Theme.bright_green;
        if (temp < neutral) return Theme.green;
        if (temp < warm) return Theme.yellow;
        return Theme.red;
    }

    function pop_color(pop) {
        const p = Math.max(0, Math.min(100, pop));
        return p < 60 ? Theme.blue : Theme.bright_blue;
    }

    function unit_symbol() {
        return root.settings.unit === "celsius" ? "C" : "F";
    }

    function format_hour(date) {
        const d = date instanceof Date ? date : new Date(date);
        if (root.settings.time_format === "12h") {
            let h = d.getHours() % 12;
            if (h === 0) h = 12;
            return h + (d.getHours() < 12 ? "am" : "pm");
        }
        const hh = d.getHours();
        return hh < 10 ? "0" + hh : "" + hh;
    }

    // --- Wind, pressure, visibility, UV and AQI: units and bands ---

    readonly property var wind_dir_names: ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    function wind_dir_label(deg) {
        const idx = Math.round(((deg % 360) + 360) % 360 / 45) % 8;
        return root.wind_dir_names[idx];
    }

    function wind_unit() {
        return root.settings.unit === "celsius" ? "km/h" : "mph";
    }

    function pressure_display(hpa) {
        if (root.settings.unit === "celsius") return Math.round(hpa) + " hPa";
        return (hpa * 0.0295299831).toFixed(2) + " inHg";
    }

    function visibility_display(meters) {
        if (root.settings.unit === "celsius") return (meters / 1000).toFixed(1) + " km";
        return (meters / 1609.344).toFixed(1) + " mi";
    }

    readonly property var uv_bands: [
        { limit: 3, label: "Low", color_key: "green" },
        { limit: 6, label: "Moderate", color_key: "yellow" },
        { limit: 8, label: "High", color_key: "warning" },
        { limit: 11, label: "Very High", color_key: "red" },
        { limit: Infinity, label: "Extreme", color_key: "magenta" }
    ]

    function uv_band(uv) {
        for (const band of root.uv_bands) {
            if (uv < band.limit) return band;
        }
        return root.uv_bands[root.uv_bands.length - 1];
    }

    function uv_color(uv) {
        return root.color_for_key(root.uv_band(uv).color_key);
    }

    readonly property var aqi_bands: [
        { limit: 51, label: "Good", color_key: "green" },
        { limit: 101, label: "Moderate", color_key: "yellow" },
        { limit: 151, label: "Unhealthy for Sensitive Groups", color_key: "warning" },
        { limit: 201, label: "Unhealthy", color_key: "red" },
        { limit: 301, label: "Very Unhealthy", color_key: "magenta" },
        { limit: Infinity, label: "Hazardous", color_key: "bright_red" }
    ]

    function aqi_band(aqi) {
        for (const band of root.aqi_bands) {
            if (aqi < band.limit) return band;
        }
        return root.aqi_bands[root.aqi_bands.length - 1];
    }

    function aqi_color(aqi) {
        return root.color_for_key(root.aqi_band(aqi).color_key);
    }

    function color_for_key(key) {
        switch (key) {
        case "green": return Theme.green;
        case "yellow": return Theme.yellow;
        case "warning": return Theme.warning;
        case "red": return Theme.red;
        case "magenta": return Theme.magenta;
        case "bright_red": return Theme.bright_red;
        default: return Theme.fg_core;
        }
    }
}
