//! monitor position words and slots (was monitor-words.sh; monitor-places.jq stays until the 3.3 provider)
use super::speech::spoken_position;
use serde::Deserialize;

const POSITION_WORDS: [&str; 7] = ["left", "right", "middle", "center", "centre", "top", "bottom"];
const BUILTIN_PANEL_PREFIXES: [&str; 3] = ["eDP-", "LVDS-", "DSI-"];

/// A connected monitor as `monitor-places.jq` and overview.json's "monitors" describe it.
#[derive(Clone, Debug, Deserialize)]
pub struct Place {
    pub id: String,
    /// 1-based; 0 when Hyprland's slot lookup does not list the monitor.
    pub slot: i64,
    pub horizontal: String,
    pub vertical: String,
}

/// The monitor words without "the", and without "monitor", "screen" or "display" around them.
fn without_noise(words: &str) -> &str {
    let mut words = words.strip_prefix("the ").unwrap_or(words);
    for noun in [" monitor", " screen", " display"] {
        words = words.strip_suffix(noun).unwrap_or(words);
    }
    for noun in ["monitor ", "screen ", "display "] {
        words = words.strip_prefix(noun).unwrap_or(words);
    }
    words
}

/// Whether every word is one this module understands, so "system monitor" is left to the apps and "bottom right" is
/// answered even when no monitor sits there.
pub fn words_known(words: &str) -> bool {
    let words = without_noise(words);
    if words.is_empty() {
        return false;
    }
    let known = |word: &str| {
        POSITION_WORDS.contains(&word)
            || matches!(word, "laptop" | "builtin" | "built" | "in" | "internal" | "number")
            || spoken_position(word).is_some()
    };
    words.split_whitespace().all(known)
}

/// The id of the monitor the words name, or `Err` with the sentence to tell the user ("no left monitor").
pub fn named(words: &str, monitors: &[Place]) -> Result<String, String> {
    let words = without_noise(words);
    let words = words
        .strip_prefix("number ")
        .unwrap_or(words)
        .replace("center", "middle")
        .replace("centre", "middle");
    let mut description = format!("{words} monitor");
    let mut slot_asked = None;
    let found: Vec<&Place> = if matches!(words.as_str(), "laptop" | "builtin" | "built in" | "internal") {
        monitors
            .iter()
            .filter(|place| BUILTIN_PANEL_PREFIXES.iter().any(|prefix| place.id.starts_with(prefix)))
            .collect()
    } else if let Some(slot) = spoken_position(&words) {
        description = format!("monitor {words}");
        slot_asked = Some(slot);
        monitors.iter().filter(|place| place.slot == slot && slot > 0).collect()
    } else {
        // jq's split on the empty string is an empty list, which every monitor satisfies.
        let spoken: Vec<&str> = if words.is_empty() {
            Vec::new()
        } else {
            words.split(' ').collect()
        };
        monitors
            .iter()
            .filter(|place| {
                spoken
                    .iter()
                    .all(|word| place.horizontal == *word || place.vertical == *word)
            })
            .collect()
    };
    match found.as_slice() {
        [only] => Ok(only.id.clone()),
        [] => match slot_asked {
            // A monitor with no known slot may be the one asked for, so the answer is "can't tell", not "no such monitor".
            Some(slot) if monitors.iter().any(|place| place.slot == 0) => {
                Err(format!("can't tell which monitor is slot {slot}"))
            }
            _ => Err(format!("no {description}")),
        },
        _ => Err(format!("more than one {description}")),
    }
}
