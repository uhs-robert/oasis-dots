//! `click-target`: the window the OCR coordinates belong to, for the click that follows. A picker can wait seconds
//! before the click, and by then another window, or this one moved, may sit under the point.
use super::covering::jq_equal;
use serde_json::{Value, json};
use std::io::Write;
use std::os::unix::fs::DirBuilderExt;
use std::path::PathBuf;

/// How long the record is trusted: a click that waits on a picker for longer lands on a screen nobody looked at.
const MAX_AGE_SECS: f64 = 60.0;

fn runtime_dir() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .filter(|dir| !dir.is_empty())
        .map_or_else(|| "/tmp".into(), PathBuf::from)
}

fn path() -> PathBuf {
    runtime_dir().join("voxcmd").join("click-target")
}

/// Written whole to a file of the process's own, then renamed into place, so a reader never sees half of it.
pub fn write(window: &Value) -> std::io::Result<()> {
    let dir = path().parent().map(PathBuf::from).unwrap_or_default();
    std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&dir)?;
    let captured_at = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |since| since.as_secs());
    let staged = dir.join(format!("click-target.{}", std::process::id()));
    let mut file = std::fs::File::create(&staged)?;
    writeln!(file, "{}", json!({"captured_at": captured_at, "window": window}))?;
    std::fs::rename(&staged, path())
}

/// What `jq`'s `identity` makes of a window: `{id: .stableId // .address, at, size}`. `//` falls back on null and false
/// only, so an empty stableId stays the id.
fn identity(window: &Value) -> [Value; 3] {
    let field = |name: &str| window.get(name).cloned().unwrap_or(Value::Null);
    let stable_id = field("stableId");
    let id = if matches!(stable_id, Value::Null | Value::Bool(false)) {
        field("address")
    } else {
        stable_id
    };
    [id, field("at"), field("size")]
}

/// Whether `current` (what Hyprland says is focused now) is still the window the capture recorded, at the same place
/// and size, and the record is recent. Anything else means the captured coordinates may now point at other content,
/// and so does no record. `current` asks Hyprland only once there is a record to compare it with.
pub fn window_unchanged(current: impl FnOnce() -> Value, now_secs: u64) -> bool {
    let Ok(text) = std::fs::read_to_string(path()) else {
        return false;
    };
    window_unchanged_in(&text, &current(), now_secs)
}

fn window_unchanged_in(record: &str, current: &Value, now_secs: u64) -> bool {
    let Ok(record) = serde_json::from_str::<Value>(record) else {
        return false;
    };
    let Some(captured_at) = record.get("captured_at").and_then(Value::as_f64) else {
        return false;
    };
    let Some(window) = record.get("window") else {
        return false;
    };
    now_secs as f64 - captured_at <= MAX_AGE_SECS
        && window.get("at").is_some_and(|at| !at.is_null())
        && identity(window)
            .iter()
            .zip(identity(current))
            .all(|(recorded, now)| jq_equal(recorded, &now))
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: u64 = 1_000_000;

    fn record(captured_at: u64, window: &Value) -> String {
        json!({"captured_at": captured_at, "window": window}).to_string()
    }

    fn window() -> Value {
        json!({"address": "0x2001", "at": [100, 50], "size": [160, 96], "stableId": "18000004"})
    }

    fn unchanged(window_now: &Value) -> bool {
        window_unchanged_in(&record(NOW - 1, &window()), window_now, NOW)
    }

    #[test]
    fn the_same_window_is_unchanged() {
        assert!(unchanged(&window()));
    }

    #[test]
    fn another_window_a_move_a_resize_or_no_window_is_a_change() {
        let mut other = window();
        other["stableId"] = json!("18000009");
        assert!(!unchanged(&other));
        let mut moved = window();
        moved["at"] = json!([300, 50]);
        assert!(!unchanged(&moved));
        let mut resized = window();
        resized["size"] = json!([400, 96]);
        assert!(!unchanged(&resized));
        assert!(!unchanged(&json!({})));
    }

    #[test]
    fn a_window_that_is_otherwise_the_same_but_for_a_new_address_is_unchanged() {
        // The id is the stableId when there is one: the address is only the fallback.
        let mut reopened = window();
        reopened["address"] = json!("0x9999");
        assert!(unchanged(&reopened));
    }

    #[test]
    fn a_missing_or_false_stable_id_falls_back_to_the_address_but_an_empty_one_does_not() {
        let bare = json!({"address": "0x2001", "at": [100, 50], "size": [160, 96]});
        assert!(window_unchanged_in(&record(NOW, &bare), &bare, NOW));
        let mut moved_address = bare.clone();
        moved_address["address"] = json!("0x3001");
        assert!(!window_unchanged_in(&record(NOW, &bare), &moved_address, NOW));
        let mut false_id = bare.clone();
        false_id["stableId"] = json!(false);
        assert!(window_unchanged_in(&record(NOW, &bare), &false_id, NOW));
        assert!(!window_unchanged_in(&record(NOW, &false_id), &moved_address, NOW));
        // An empty stableId is an id of its own: two windows with one are the same window whatever their address.
        let mut empty = bare.clone();
        empty["stableId"] = json!("");
        let mut empty_elsewhere = moved_address.clone();
        empty_elsewhere["stableId"] = json!("");
        assert!(window_unchanged_in(&record(NOW, &empty), &empty_elsewhere, NOW));
        assert!(!window_unchanged_in(&record(NOW, &empty), &moved_address, NOW));
    }

    #[test]
    fn float_and_integer_numbers_are_the_same_geometry() {
        let mut floats = window();
        floats["at"] = json!([100.0, 50.0]);
        floats["size"] = json!([160.0, 96.0]);
        assert!(unchanged(&floats));
    }

    #[test]
    fn the_record_is_trusted_for_a_minute_and_not_longer() {
        assert!(window_unchanged_in(&record(NOW - 60, &window()), &window(), NOW));
        assert!(!window_unchanged_in(&record(NOW - 61, &window()), &window(), NOW));
    }

    #[test]
    fn a_record_without_a_position_or_a_time_or_not_json_is_untrusted() {
        let mut no_position = window();
        no_position.as_object_mut().unwrap().remove("at");
        assert!(!window_unchanged_in(&record(NOW, &no_position), &no_position, NOW));
        assert!(!window_unchanged_in("{\"window\": {}}", &window(), NOW));
        assert!(!window_unchanged_in("not json", &window(), NOW));
        assert!(!window_unchanged_in("", &window(), NOW));
    }
}
