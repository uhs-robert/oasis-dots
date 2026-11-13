//! `monitors`: the candidate of a monitor phrase is the one monitor its words name, or the reason none fits. The port of
//! monitors.sh's `monitor_candidates` and of monitor-places.jq, which gives each monitor its words.
//!
//! A failure is one candidate whose id is `error:<why>` and whose label is the why, which fails the action. Words that
//! are no monitor vocabulary at all ("system monitor") list nothing, which leaves the phrase to the apps.
use super::BuiltinHooks;
use crate::config::schema::Integration;
use crate::hooks::{Candidate, HookQuery, HookRun, Lookup};
use crate::hypr;
use crate::paths;
use crate::process;
use crate::text::monitors::{self, Place};
use serde_json::Value;
use std::process::Command;
use std::time::{Duration, Instant};

const BUILTIN_WORDS: [&str; 4] = ["laptop", "builtin", "built in", "internal"];
/// The monitor list may take 2 s (hypr.rs), so a hung Hyprland costs 3 s in all, the budget the shell hook had.
const SLOT_LOOKUP_WITHIN: Duration = Duration::from_secs(1);

impl BuiltinHooks {
    pub(super) fn monitors(&self, integration: &Integration, query: &HookQuery) -> HookRun {
        let mut run = HookRun::unhooked(
            integration,
            query.action,
            &format!("monitors {} {}", query.action, query.target),
        );
        run.exit = Some(0);
        run.lookup = Lookup::Candidates(Vec::new());
        let target = query.target;
        let understood = if query.action.ends_with("_laptop") {
            BUILTIN_WORDS.contains(&target.strip_prefix("the ").unwrap_or(target))
        } else {
            monitors::words_known(target)
        };
        if understood {
            let started = Instant::now();
            let named = monitors::named(target, &places());
            let id = named.unwrap_or_else(|sentence| format!("error:{sentence}"));
            let label = id.strip_prefix("error:").unwrap_or(&id).to_string();
            let found = vec![Candidate {
                id,
                label,
                match_text: Some(target.to_string()),
                weak: false,
            }];
            run.millis = started.elapsed().as_secs_f64() * 1000.0;
            run.lines.clone_from(&found);
            run.lookup = Lookup::Candidates(found);
        }
        run
    }
}

/// The names of the monitor in each slot, space separated ("-" for an empty one). Hyprland's Lua owns the slot order and
/// `hyprctl eval` prints nothing back, so the answer goes through a file, as the overview gets it. Empty when Hyprland
/// cannot answer, which leaves every slot unknown.
fn slot_names() -> String {
    let file = paths::runtime_dir().join("monitor-slots");
    if let Some(dir) = file.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::remove_file(&file);
    let lua = format!(
        "local W = require('lib.workspaces'); local t = {{}}; for i = 1, 10 do t[i] = W.get_monitor_for_slot(i) or '-' end; \
         local f = io.open('{}', 'w'); f:write(table.concat(t, ' ')); f:close()",
        file.display()
    );
    let _ = process::run_with_timeout(Command::new("hyprctl").args(["eval", &lua]), SLOT_LOOKUP_WITHIN);
    std::fs::read_to_string(&file).unwrap_or_default()
}

/// The connected monitors with their words and slots. None when Hyprland does not list monitors.
fn places() -> Vec<Place> {
    places_from(hypr::monitors(), slot_names)
}

/// No monitor list is no places, and then the slot lookup is not asked.
fn places_from(monitors: Option<Value>, slot_names: impl FnOnce() -> String) -> Vec<Place> {
    match monitors {
        Some(monitors) => places_of(&monitors, &slot_names()),
        None => Vec::new(),
    }
}

/// A monitor as monitor-places.jq reads it: its box in logical pixels, turned monitors swapping width and height.
struct Group {
    name: String,
    x: f64,
    y: f64,
    w: f64,
    h: f64,
}

/// What monitor-places.jq prints for `hyprctl monitors -j` and the slot names, in slot order. It mirrors `positions()`
/// and `slot_order()` in features/overview/Voice.js. A monitor no slot names gets slot 0 (unknown), never a guessed
/// one: the slot order is Hyprland's, and a guess would send "monitor one" to the wrong display.
pub(super) fn places_of(monitors: &Value, slot_names: &str) -> Vec<Place> {
    let number = |monitor: &Value, key: &str| monitor.get(key).and_then(Value::as_f64).unwrap_or(0.0);
    let groups: Vec<Group> = monitors
        .as_array()
        .into_iter()
        .flatten()
        .filter(|monitor| monitor.get("disabled").and_then(Value::as_bool) != Some(true))
        .map(|monitor| {
            let scale = if number(monitor, "scale") > 0.0 {
                number(monitor, "scale")
            } else {
                1.0
            };
            let turned = monitor.get("transform").and_then(Value::as_i64).unwrap_or(0) % 2 == 1;
            let (width, height) = (number(monitor, "width"), number(monitor, "height"));
            let (w, h) = if turned { (height, width) } else { (width, height) };
            Group {
                name: monitor
                    .get("name")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                x: number(monitor, "x"),
                y: number(monitor, "y"),
                w: w / scale,
                h: h / scale,
            }
        })
        .collect();

    let all: Vec<usize> = (0..groups.len()).collect();
    let row_list = rows(&groups, &all);
    let vertical = cluster_words(&row_list, ["top", "bottom"], ["top", "middle", "bottom"]);
    let mut horizontal = Vec::new();
    for row in &row_list {
        let clusters = x_clusters(&groups, row);
        horizontal.extend(cluster_words(&clusters, ["left", "right"], ["left", "middle", "right"]));
    }
    let word_of = |words: &[(usize, &'static str)], index: usize| {
        words
            .iter()
            .find(|(i, _)| *i == index)
            .map_or("", |(_, word)| word)
            .to_string()
    };
    let named: Vec<&str> = slot_names.split(' ').filter(|name| !name.is_empty()).collect();
    let mut places: Vec<Place> = groups
        .iter()
        .enumerate()
        .map(|(index, group)| Place {
            id: group.name.clone(),
            slot: named
                .iter()
                .position(|name| *name == group.name)
                .map_or(0, |position| position as i64 + 1),
            horizontal: word_of(&horizontal, index),
            vertical: word_of(&vertical, index),
        })
        .collect();
    // Stable, as jq's sort_by is: monitors without a slot keep their order after the slotted ones.
    places.sort_by_key(|place| if place.slot == 0 { 1000 } else { place.slot });
    places
}

/// The words of `count` rows or columns: the ends are named, and a middle one only when there is exactly one.
fn words_for(count: usize, two: [&'static str; 2], three: [&'static str; 3]) -> Vec<&'static str> {
    match count {
        2 => two.to_vec(),
        3 => three.to_vec(),
        count if count > 3 => {
            let mut words = vec![three[0]];
            words.extend(std::iter::repeat_n("", count - 2));
            words.push(three[2]);
            words
        }
        _ => Vec::new(),
    }
}

/// Each monitor index of each cluster with its cluster's word ("" past the named ones).
fn cluster_words(
    clusters: &[Vec<usize>],
    two: [&'static str; 2],
    three: [&'static str; 3],
) -> Vec<(usize, &'static str)> {
    let names = words_for(clusters.len(), two, three);
    clusters
        .iter()
        .enumerate()
        .flat_map(|(k, cluster)| {
            let word = names.get(k).copied().unwrap_or("");
            cluster.iter().map(move |&i| (i, word))
        })
        .collect()
}

/// Monitors that overlap along x share a cluster; the clusters are in order along x.
fn x_clusters(groups: &[Group], members: &[usize]) -> Vec<Vec<usize>> {
    let mut sorted = members.to_vec();
    sorted.sort_by(|&a, &b| groups[a].x.total_cmp(&groups[b].x).then(a.cmp(&b)));
    let mut clusters: Vec<Vec<usize>> = Vec::new();
    let mut end = 0.0_f64;
    for i in sorted {
        let group = &groups[i];
        match clusters.last_mut() {
            Some(last) if group.x < end => {
                last.push(i);
                end = end.max(group.x + group.w);
            }
            _ => {
                clusters.push(vec![i]);
                end = group.x + group.w;
            }
        }
    }
    clusters
}

/// A monitor joins the row while its top is above every member's bottom, so a tall neighbour sharing the top edge stays
/// in it; one starting at or below the shortest member's bottom starts a new row.
fn rows(groups: &[Group], members: &[usize]) -> Vec<Vec<usize>> {
    let mut sorted = members.to_vec();
    sorted.sort_by(|&a, &b| {
        groups[a]
            .y
            .total_cmp(&groups[b].y)
            .then(groups[a].h.total_cmp(&groups[b].h))
            .then(a.cmp(&b))
    });
    let mut rows: Vec<Vec<usize>> = Vec::new();
    let mut bottom = 0.0_f64;
    for i in sorted {
        let group = &groups[i];
        match rows.last_mut() {
            Some(last) if group.y < bottom => {
                last.push(i);
                bottom = bottom.min(group.y + group.h);
            }
            _ => {
                rows.push(vec![i]);
                bottom = group.y + group.h;
            }
        }
    }
    rows
}

#[cfg(test)]
mod tests {
    use super::*;

    fn words(layout: &str, slots: &str) -> Vec<(String, i64, String, String)> {
        let path = format!("{}/tests/fixtures/monitors/{layout}.json", env!("CARGO_MANIFEST_DIR"));
        let monitors: Value = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        places_of(&monitors, slots)
            .into_iter()
            .map(|place| (place.id, place.slot, place.horizontal, place.vertical))
            .collect()
    }

    fn row(id: &str, slot: i64, horizontal: &str, vertical: &str) -> (String, i64, String, String) {
        (id.into(), slot, horizontal.into(), vertical.into())
    }

    #[test]
    fn a_laptop_below_a_row_of_three_is_bottom_and_the_three_are_left_middle_right() {
        assert_eq!(
            words("owner", "DP-8 HDMI-A-1 DP-13 eDP-1"),
            [
                row("DP-8", 1, "left", "top"),
                row("HDMI-A-1", 2, "middle", "top"),
                row("DP-13", 3, "right", "top"),
                row("eDP-1", 4, "", "bottom"),
            ]
        );
    }

    #[test]
    fn a_monitor_no_slot_names_has_slot_zero_and_sorts_last() {
        let places = words("owner", "HDMI-A-1 - DP-8");
        let slots: Vec<(&str, i64)> = places.iter().map(|place| (place.0.as_str(), place.1)).collect();
        assert_eq!(slots, [("HDMI-A-1", 1), ("DP-8", 3), ("eDP-1", 0), ("DP-13", 0)]);
    }

    /// The jq outputs in tests/fixtures/monitor-places/, named `<layout>.<slot names, spaces as _>.json` ("none": no
    /// slot names), are what monitor-places.jq printed for the layout in tests/fixtures/monitors/.
    #[test]
    fn every_stored_jq_output_is_what_the_rust_port_gives() {
        let fixtures = format!("{}/tests/fixtures", env!("CARGO_MANIFEST_DIR"));
        let mut checked = 0;
        for entry in std::fs::read_dir(format!("{fixtures}/monitor-places")).unwrap() {
            let path = entry.unwrap().path();
            let name = path.file_stem().unwrap().to_str().unwrap().to_string();
            let (layout, slots) = name.split_once('.').unwrap();
            let slots = if slots == "none" {
                String::new()
            } else {
                slots.replace('_', " ")
            };
            let monitors: Value =
                serde_json::from_str(&std::fs::read_to_string(format!("{fixtures}/monitors/{layout}.json")).unwrap())
                    .unwrap();
            let expected: Vec<Value> = serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
            let expected: Vec<(String, i64, String, String)> = expected
                .iter()
                .map(|place| {
                    let text = |key: &str| place[key].as_str().unwrap().to_string();
                    (
                        text("id"),
                        place["slot"].as_i64().unwrap(),
                        text("horizontal"),
                        text("vertical"),
                    )
                })
                .collect();
            let got: Vec<_> = places_of(&monitors, &slots)
                .into_iter()
                .map(|place| (place.id, place.slot, place.horizontal, place.vertical))
                .collect();
            assert_eq!(got, expected, "{name}");
            checked += 1;
        }
        assert!(checked >= 30, "only {checked} stored outputs: was the directory lost?");
    }

    #[test]
    fn no_monitor_list_gives_no_places_and_skips_the_slot_lookup() {
        let asked = std::cell::Cell::new(false);
        let lookup = || {
            asked.set(true);
            "DP-1".to_string()
        };
        assert!(places_from(None, lookup).is_empty());
        assert!(!asked.get());
        assert!(places_of(&serde_json::json!({"not": "a list"}), "DP-1").is_empty());
    }
}
