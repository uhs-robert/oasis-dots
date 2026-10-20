//! Whether something drawn above the captured window hides a click point: the port of `drop_covered`'s jq.
//!
//! The capture (`grim -T`) is the window's own buffer, so OCR also reads text that is covered on screen. Covering is a
//! floating window over a tiled one, a pinned window over an unpinned one, and the monitor's reserved edges (the bar and
//! other layer-shell surfaces). Between two floating windows the order is unknown, and the focused one is raised, so
//! neither covers. Whatever Hyprland cannot answer covers nothing.
use serde_json::Value;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Cover {
    AnotherWindow,
    ReservedEdge,
}

impl std::fmt::Display for Cover {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(match self {
            Self::AnotherWindow => "another window",
            Self::ReservedEdge => "a reserved edge (the bar)",
        })
    }
}

/// jq's truthiness: everything but null and false (so `0` and `""` are true).
fn truthy(value: Option<&Value>) -> bool {
    !matches!(value, None | Some(Value::Null | Value::Bool(false)))
}

/// jq's `==`: 100 and 100.0 are the same number, which serde_json's `Value` equality does not say.
pub fn jq_equal(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Number(a), Value::Number(b)) => a.as_f64() == b.as_f64(),
        (Value::Array(a), Value::Array(b)) => a.len() == b.len() && a.iter().zip(b).all(|(a, b)| jq_equal(a, b)),
        (Value::Object(a), Value::Object(b)) => {
            a.len() == b.len() && a.iter().all(|(key, a)| b.get(key).is_some_and(|b| jq_equal(a, b)))
        }
        _ => a == b,
    }
}

fn field<'a>(value: &'a Value, name: &str) -> &'a Value {
    value.get(name).unwrap_or(&Value::Null)
}

fn workspace_id(window: &Value) -> &Value {
    window
        .get("workspace")
        .map_or(&Value::Null, |workspace| field(workspace, "id"))
}

/// `[x, y]` or `[w, h]` as numbers; None when the field is not two numbers.
fn pair(window: &Value, name: &str) -> Option<(f64, f64)> {
    let list = window.get(name)?.as_array()?;
    Some((list.first()?.as_f64()?, list.get(1)?.as_f64()?))
}

/// The jq's `inside`: left and top inclusive, right and bottom exclusive.
fn inside(x: f64, y: f64, left: f64, top: f64, width: f64, height: f64) -> bool {
    x >= left && x < left + width && y >= top && y < top + height
}

/// Whether the client is drawn above the active window: mapped, shown, positioned, another window, on the same
/// workspace or pinned, and either pinned over an unpinned one or floating over a tiled one.
fn is_above(client: &Value, active: &Value) -> bool {
    let (pinned, floating) = (truthy(client.get("pinned")), truthy(client.get("floating")));
    let active_pinned = truthy(active.get("pinned"));
    truthy(client.get("mapped"))
        && !truthy(client.get("hidden"))
        && !field(client, "at").is_null()
        && !jq_equal(field(client, "address"), field(active, "address"))
        && (jq_equal(workspace_id(client), workspace_id(active)) || pinned)
        && ((pinned && !active_pinned) || (floating && !truthy(active.get("floating"))))
}

/// A monitor's logical rectangle `(x, y, w, h)`: its pixels turned upright for a rotated one and divided by the scale.
/// A monitor without numbers for these (or a scale of zero or less, where jq would abort) is skipped.
fn logical_screen(monitor: &Value) -> Option<(f64, f64, f64, f64)> {
    let number = |name: &str| monitor.get(name)?.as_f64();
    let (width, height) = (number("width")?, number("height")?);
    let scale = number("scale")?;
    if scale <= 0.0 {
        return None;
    }
    // jq's % truncates both sides to integers.
    let rotated = monitor
        .get("transform")
        .and_then(Value::as_f64)
        .map_or(0, |value| (value as i64) % 2)
        == 1;
    let (width, height) = if rotated { (height, width) } else { (width, height) };
    Some((number("x")?, number("y")?, width / scale, height / scale))
}

/// The reserved edges as left, top, right, bottom, zero where absent.
fn reserved_of(monitor: &Value) -> [f64; 4] {
    let list = monitor.get("reserved").filter(|reserved| truthy(Some(reserved)));
    let mut edges = [0.0; 4];
    if let Some(list) = list.and_then(Value::as_array) {
        for (edge, value) in edges.iter_mut().zip(list) {
            *edge = value.as_f64().unwrap_or(0.0);
        }
    }
    edges
}

/// What covers the point `(x, y)` of a capture of `active`, the window above it first and the bar after. `clients`
/// and `monitors` are Hyprland's lists; anything but a list covers nothing.
pub fn covered_by(x: i64, y: i64, active: &Value, clients: &Value, monitors: &Value) -> Option<Cover> {
    let (x, y) = (x as f64, y as f64);
    let over_window = clients.as_array().is_some_and(|clients| {
        clients
            .iter()
            .filter(|client| is_above(client, active))
            .filter_map(|client| Some((pair(client, "at")?, pair(client, "size")?)))
            .any(|((left, top), (width, height))| inside(x, y, left, top, width, height))
    });
    if over_window {
        return Some(Cover::AnotherWindow);
    }
    let under_edge = monitors.as_array().is_some_and(|monitors| {
        monitors.iter().any(|monitor| {
            let Some((left, top, width, height)) = logical_screen(monitor) else {
                return false;
            };
            let [reserved_left, reserved_top, reserved_right, reserved_bottom] = reserved_of(monitor);
            inside(x, y, left, top, width, height)
                && (x < left + reserved_left
                    || y < top + reserved_top
                    || x >= left + width - reserved_right
                    || y >= top + height - reserved_bottom)
        })
    });
    under_edge.then_some(Cover::ReservedEdge)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn client(address: &str, at: [i64; 2], size: [i64; 2], floating: bool, pinned: bool, workspace: i64) -> Value {
        json!({"address": address, "at": at, "size": size, "floating": floating, "pinned": pinned,
               "workspace": {"id": workspace}, "mapped": true, "hidden": false})
    }

    fn monitor(width: i64, height: i64, reserved: [i64; 4]) -> Value {
        json!({"id": 0, "width": width, "height": height, "scale": 1, "transform": 0, "x": 0, "y": 0, "reserved": reserved})
    }

    fn plain_monitors() -> Value {
        json!([monitor(1920, 1080, [0, 0, 0, 0])])
    }

    const POINT: (i64, i64) = (175, 82);

    fn tiled() -> Value {
        client("0x2001", [100, 50], [160, 96], false, false, 1)
    }

    fn cover_by(others: &[Value], active: &Value, monitors: &Value) -> Option<Cover> {
        let mut clients = vec![active.clone()];
        clients.extend(others.iter().cloned());
        covered_by(POINT.0, POINT.1, active, &Value::Array(clients), monitors)
    }

    fn above(other: Value) -> Option<Cover> {
        cover_by(&[other], &tiled(), &plain_monitors())
    }

    #[test]
    fn a_floating_window_over_a_tiled_one_covers() {
        let floating = client("0x3001", [150, 50], [60, 60], true, false, 1);
        assert_eq!(above(floating), Some(Cover::AnotherWindow));
    }

    #[test]
    fn a_tiled_window_beside_covers_nothing() {
        assert_eq!(above(client("0x3001", [150, 50], [60, 60], false, false, 1)), None);
    }

    #[test]
    fn a_floating_window_on_another_workspace_covers_nothing_but_a_pinned_one_covers_from_anywhere() {
        assert_eq!(above(client("0x3001", [150, 50], [60, 60], true, false, 2)), None);
        assert_eq!(
            above(client("0x3001", [150, 50], [60, 60], true, true, 2)),
            Some(Cover::AnotherWindow)
        );
    }

    #[test]
    fn an_unmapped_or_hidden_window_covers_nothing() {
        let mut unmapped = client("0x3001", [150, 50], [60, 60], true, false, 1);
        unmapped["mapped"] = json!(false);
        assert_eq!(above(unmapped), None);
        let mut hidden = client("0x3001", [150, 50], [60, 60], true, false, 1);
        hidden["hidden"] = json!(true);
        assert_eq!(above(hidden), None);
    }

    #[test]
    fn a_pinned_tiled_window_covers_an_unpinned_one() {
        assert_eq!(
            above(client("0x3001", [150, 50], [60, 60], false, true, 1)),
            Some(Cover::AnotherWindow)
        );
    }

    #[test]
    fn between_two_floating_windows_neither_covers() {
        let active = client("0x2001", [100, 50], [160, 96], true, false, 1);
        let other = client("0x3001", [150, 50], [60, 60], true, false, 1);
        assert_eq!(cover_by(&[other], &active, &plain_monitors()), None);
    }

    #[test]
    fn a_pinned_window_does_not_cover_a_pinned_focused_one_unless_it_floats_over_a_tiled_one() {
        let active = client("0x2001", [100, 50], [160, 96], false, true, 1);
        let other = client("0x3001", [150, 50], [60, 60], false, true, 1);
        assert_eq!(cover_by(&[other], &active, &plain_monitors()), None);
    }

    #[test]
    fn the_active_window_never_covers_itself() {
        let mut clients = json!([tiled()]);
        clients[0]["floating"] = json!(true);
        let active = tiled();
        assert_eq!(covered_by(POINT.0, POINT.1, &active, &clients, &plain_monitors()), None);
    }

    #[test]
    fn the_edges_of_a_covering_window_are_left_inclusive_and_right_exclusive() {
        let over = |left: i64| client("0x3001", [left, 50], [60, 60], true, false, 1);
        // The window spans 60 columns: x = 175 is its first at left = 175 and just past its last at left = 115.
        assert_eq!(above(over(175)), Some(Cover::AnotherWindow));
        assert_eq!(above(over(176)), None);
        assert_eq!(above(over(116)), Some(Cover::AnotherWindow));
        assert_eq!(above(over(115)), None);
    }

    #[test]
    fn each_reserved_edge_covers_its_band_and_nothing_beside_it() {
        let covered = |reserved: [i64; 4], width: i64, height: i64| {
            cover_by(&[], &tiled(), &json!([monitor(width, height, reserved)]))
        };
        assert_eq!(covered([0, 100, 0, 0], 1920, 1080), Some(Cover::ReservedEdge));
        assert_eq!(
            covered([0, 82, 0, 0], 1920, 1080),
            None,
            "y = 82 is the first row below an 82-high bar"
        );
        assert_eq!(covered([0, 83, 0, 0], 1920, 1080), Some(Cover::ReservedEdge));
        assert_eq!(covered([200, 0, 0, 0], 1920, 1080), Some(Cover::ReservedEdge));
        assert_eq!(
            covered([175, 0, 0, 0], 1920, 1080),
            None,
            "x = 175 is the first column right of a 175-wide edge"
        );
        assert_eq!(covered([0, 0, 950, 0], 1080, 1920), Some(Cover::ReservedEdge));
        assert_eq!(covered([0, 0, 0, 1000], 1920, 1080), Some(Cover::ReservedEdge));
        assert_eq!(covered([0, 0, 0, 0], 1920, 1080), None);
    }

    #[test]
    fn a_rotated_monitor_swaps_its_width_and_height() {
        let mut rotated = monitor(1080, 1920, [0, 0, 950, 0]);
        rotated["transform"] = json!(1);
        assert_eq!(cover_by(&[], &tiled(), &json!([rotated.clone()])), None);
        rotated["transform"] = json!(3);
        assert_eq!(cover_by(&[], &tiled(), &json!([rotated.clone()])), None);
        rotated["transform"] = json!(2);
        assert_eq!(cover_by(&[], &tiled(), &json!([rotated])), Some(Cover::ReservedEdge));
    }

    #[test]
    fn the_scale_divides_the_monitor_into_logical_pixels() {
        // 3840x2160 at scale 2 is 1920x1080 logical, so a 1750 edge starts at x = 170 and covers 175; unscaled the
        // monitor is 3840 wide and the same edge starts at 2090.
        let mut scaled = monitor(3840, 2160, [0, 0, 1750, 0]);
        scaled["scale"] = json!(2);
        assert_eq!(
            cover_by(&[], &tiled(), &json!([scaled.clone()])),
            Some(Cover::ReservedEdge)
        );
        scaled["scale"] = json!(1);
        assert_eq!(cover_by(&[], &tiled(), &json!([scaled.clone()])), None);
        scaled["scale"] = json!(0);
        assert_eq!(
            cover_by(&[], &tiled(), &json!([scaled])),
            None,
            "a zero scale skips the monitor"
        );
    }

    #[test]
    fn a_second_monitor_at_an_offset_covers_only_its_own_points() {
        // A bar on a monitor placed right of the first: its band is at x 1920.., so a point on the first is untouched.
        let first = monitor(1920, 1080, [0, 0, 0, 0]);
        let mut second = monitor(1920, 1080, [0, 100, 0, 0]);
        second["x"] = json!(1920);
        let monitors = json!([first, second]);
        assert_eq!(covered_by(175, 82, &tiled(), &json!([]), &monitors), None);
        assert_eq!(
            covered_by(2000, 50, &tiled(), &json!([]), &monitors),
            Some(Cover::ReservedEdge)
        );
        assert_eq!(covered_by(2000, 150, &tiled(), &json!([]), &monitors), None);
        // A monitor left of the origin has negative logical coordinates.
        let mut left = monitor(1920, 1080, [0, 40, 0, 0]);
        left["x"] = json!(-1920);
        assert_eq!(
            covered_by(-1000, 20, &tiled(), &json!([]), &json!([left.clone()])),
            Some(Cover::ReservedEdge)
        );
        assert_eq!(covered_by(-1000, 60, &tiled(), &json!([]), &json!([left])), None);
    }

    #[test]
    fn a_window_beats_an_edge_and_both_report_their_own_reason() {
        let floating = client("0x3001", [150, 50], [60, 60], true, false, 1);
        let monitors = json!([monitor(1920, 1080, [0, 100, 0, 0])]);
        assert_eq!(cover_by(&[floating], &tiled(), &monitors), Some(Cover::AnotherWindow));
        assert_eq!(Cover::AnotherWindow.to_string(), "another window");
        assert_eq!(Cover::ReservedEdge.to_string(), "a reserved edge (the bar)");
    }

    #[test]
    fn what_hyprland_could_not_answer_covers_nothing() {
        let active = tiled();
        assert_eq!(covered_by(175, 82, &active, &json!({}), &json!({})), None);
        assert_eq!(covered_by(175, 82, &active, &Value::Null, &Value::Null), None);
        assert_eq!(
            covered_by(175, 82, &json!({}), &json!([]), &json!([{"width": 1}])),
            None
        );
    }

    #[test]
    fn a_missing_active_address_differs_from_every_client_that_has_one() {
        let floating = client("0x3001", [150, 50], [60, 60], true, false, 1);
        let mut active = tiled();
        active.as_object_mut().unwrap().remove("address");
        assert_eq!(
            covered_by(175, 82, &active, &json!([floating]), &plain_monitors()),
            Some(Cover::AnotherWindow)
        );
    }

    #[test]
    fn json_numbers_compare_as_jq_does() {
        assert!(jq_equal(&json!(100), &json!(100.0)));
        assert!(jq_equal(&json!([100, 50]), &json!([100.0, 50])));
        assert!(!jq_equal(&json!([100, 50]), &json!([100, 51])));
        assert!(jq_equal(&json!(null), &json!(null)));
        assert!(!jq_equal(&json!(null), &json!(0)));
    }
}
