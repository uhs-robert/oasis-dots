//! frame scores to triggers: a score held high for enough frames, or a dense burst of high frames, then a cooldown
//!
//! Times are seconds on any monotonic clock, passed in, so tests drive it with a fake one.

use std::collections::VecDeque;

pub const DEFAULT_COOLDOWN_SECS: f64 = 3.0;

/// A named sensitivity of the cortana model. The numbers come from 20 recorded takes. At 3 frames in a row only 10
/// trigger at strict (0.8), 11 at balanced and 12 at relaxed: takes 03, 05, 12 and 19 score high for 1 or 2 frames, then
/// drop, and takes 11 and 13 to 17 never get there. The smoothing rule adds 03 (all levels), 05 and 12 (strict) and 10
/// (relaxed), 13 of 20 at strict, and take 19 stays out of reach because only one frame passes any threshold. The 9 run-in takes ("cortana
/// exit" in one breath) peak at 0.39 and trigger under neither rule: only retraining fixes them. Whisper confirms every
/// trigger, so a false one costs a transcription, and strict keeps those down (74 in 3.2 h of everyday audio at 0.8,
/// counted before the smoothing rule).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Level {
    Strict,
    Balanced,
    Relaxed,
}

impl Level {
    pub const NAMES: &'static str = "strict, balanced, relaxed";

    pub fn parse(name: &str) -> Option<Self> {
        match name {
            "strict" => Some(Self::Strict),
            "balanced" => Some(Self::Balanced),
            "relaxed" => Some(Self::Relaxed),
            _ => None,
        }
    }

    /// The burst rule shared by every level. K=2 of the last W=6 frames (0.48 s) with a mean of 0.3 replays on the
    /// recorded takes with no loss and no trigger on a run-in take. A lone high frame never passes K, and the mean
    /// keeps two scattered frames in a long quiet window from counting.
    pub fn smoothing(self) -> Smoothing {
        Smoothing {
            frames: 2,
            window: 6,
            mean_floor: 0.3,
        }
    }

    /// The score a frame needs and the consecutive frames that need it.
    pub fn threshold_and_frames(self) -> (f32, u32) {
        match self {
            Self::Strict => (0.8, 3),
            Self::Balanced => (0.7, 3),
            Self::Relaxed => (0.6, 3),
        }
    }
}

/// A second way to trigger: `frames` of the last `window` scores at or above the threshold, and the mean of those
/// `window` scores at or above `mean_floor`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Smoothing {
    pub frames: usize,
    pub window: usize,
    pub mean_floor: f32,
}

pub struct Decider {
    threshold: f32,
    frames: u32,
    cooldown_secs: f64,
    smoothing: Option<Smoothing>,
    recent: VecDeque<f32>,
    run: u32,
    cooldown_until: f64,
}

impl Decider {
    pub fn new(threshold: f32, frames: u32, cooldown_secs: f64) -> Self {
        Self {
            threshold,
            frames,
            cooldown_secs,
            smoothing: None,
            recent: VecDeque::new(),
            run: 0,
            cooldown_until: f64::NEG_INFINITY,
        }
    }

    pub fn with_smoothing(mut self, smoothing: Option<Smoothing>) -> Self {
        self.smoothing = smoothing;
        self
    }

    /// Forgets a phrase under way (the stream closed). The cooldown stays: a pause must not let a second trigger in.
    pub fn reset(&mut self) {
        self.run = 0;
        self.recent.clear();
    }

    /// True once, on the frame that completes the hold or the burst. That is near the end of the word, which the
    /// listener then has confirmed before anything starts. Scores during the cooldown are ignored, and do not build a
    /// run or fill the window.
    pub fn update(&mut self, score: f32, now: f64) -> bool {
        if now < self.cooldown_until {
            return false;
        }
        self.run = if score >= self.threshold { self.run + 1 } else { 0 };
        if self.run < self.frames && !self.burst(score) {
            return false;
        }
        self.reset();
        self.cooldown_until = now + self.cooldown_secs;
        true
    }

    fn burst(&mut self, score: f32) -> bool {
        let Some(smoothing) = self.smoothing else {
            return false;
        };
        if self.recent.len() == smoothing.window {
            self.recent.pop_front();
        }
        self.recent.push_back(score);
        let high = self.recent.iter().filter(|value| **value >= self.threshold).count();
        // A window not yet full counts its missing frames as silence, so the mean never rises early.
        let mean = self.recent.iter().sum::<f32>() / smoothing.window as f32;
        high >= smoothing.frames && mean >= smoothing.mean_floor
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FRAME_SECS: f64 = 0.08;

    fn decider() -> Decider {
        Decider::new(0.8, 3, 3.0)
    }

    /// The frame indexes that trigger, the scores arriving one 80 ms frame apart.
    fn feed(decider: &mut Decider, scores: &[f32]) -> Vec<usize> {
        scores
            .iter()
            .enumerate()
            .filter(|(index, score)| decider.update(**score, 100.0 + *index as f64 * FRAME_SECS))
            .map(|(index, _)| index)
            .collect()
    }

    #[test]
    fn quiet_and_near_misses_never_trigger() {
        assert!(feed(&mut decider(), &[0.0, 0.3, 0.79, 0.79, 0.79, 0.0, 0.0]).is_empty());
    }

    #[test]
    fn two_frames_alone_are_not_enough() {
        assert!(feed(&mut decider(), &[0.9, 0.95, 0.1, 0.0]).is_empty());
        assert!(
            feed(
                &mut smoothed(),
                &[0.0, 0.0, 0.0, 0.9, 0.0, 0.0, 0.0, 0.0, 0.9, 0.0, 0.0]
            )
            .is_empty()
        );
    }

    fn smoothed() -> Decider {
        let smoothing = Level::Strict.smoothing();
        decider().with_smoothing(Some(smoothing))
    }

    #[test]
    fn two_high_frames_a_dip_and_a_third_trigger_with_smoothing() {
        let scores = [0.0, 0.95, 0.9, 0.5, 0.9, 0.1];
        assert!(feed(&mut decider(), &scores).is_empty());
        assert_eq!(feed(&mut smoothed(), &scores), [2]);
    }

    #[test]
    fn a_burst_with_a_low_mean_does_not_trigger() {
        // Two frames at 0.8 in a window of 6 average 0.27, under the 0.3 floor.
        assert!(feed(&mut smoothed(), &[0.0, 0.0, 0.0, 0.0, 0.8, 0.8, 0.0, 0.0]).is_empty());
        assert_eq!(feed(&mut smoothed(), &[0.0, 0.0, 0.0, 0.0, 0.9, 0.95, 0.0, 0.0]), [5]);
    }

    #[test]
    fn a_burst_triggers_once_and_the_cooldown_holds() {
        let scores = [0.9, 0.2, 0.9, 0.2, 0.9, 0.2, 0.9, 0.2];
        assert_eq!(feed(&mut smoothed(), &scores), [2]);
    }

    #[test]
    fn reset_forgets_the_window() {
        let mut decider = smoothed();
        feed(&mut decider, &[0.9, 0.1]);
        decider.reset();
        assert!(!decider.update(0.9, 101.0), "the earlier high frame is gone");
    }

    #[test]
    fn a_dip_resets_the_run() {
        assert!(feed(&mut decider(), &[0.9, 0.9, 0.79, 0.9, 0.9, 0.1, 0.0]).is_empty());
    }

    #[test]
    fn it_triggers_on_the_frame_that_completes_the_hold() {
        assert_eq!(feed(&mut decider(), &[0.0, 0.9, 0.95, 0.99, 0.9, 0.7, 0.2, 0.0]), [3]);
    }

    #[test]
    fn a_phrase_that_keeps_scoring_high_triggers_once() {
        assert_eq!(feed(&mut decider(), &[0.9; 30]), [2]);
    }

    #[test]
    fn the_cooldown_ignores_a_second_phrase_inside_three_seconds() {
        let phrase = [0.9, 0.9, 0.9, 0.1];
        let scores: Vec<f32> = [phrase, phrase].concat();
        assert_eq!(feed(&mut decider(), &scores), [2]);
    }

    #[test]
    fn a_phrase_after_the_cooldown_triggers_again() {
        let phrase = [0.9, 0.9, 0.9, 0.1];
        // 3 s is 37.5 frames, so 40 quiet frames clear it.
        let scores: Vec<f32> = [&phrase[..], &[0.0; 40], &phrase[..]].concat();
        assert_eq!(feed(&mut decider(), &scores), [2, 46]);
    }

    #[test]
    fn the_cooldown_edge_is_exact() {
        let mut decider = decider();
        assert!(!decider.update(0.9, 10.0) && !decider.update(0.9, 10.08));
        assert!(decider.update(0.9, 10.16));
        // Cooldown ends at 13.16: a run that completes just before it does not trigger, one at it does.
        for now in [13.0, 13.04, 13.1] {
            assert!(!decider.update(0.9, now), "{now}");
        }
        assert!(!decider.update(0.9, 13.16) && !decider.update(0.9, 13.24));
        assert!(decider.update(0.9, 13.32));
    }

    #[test]
    fn scores_inside_the_cooldown_build_no_run() {
        let mut decider = decider();
        for index in 0..3 {
            decider.update(0.9, 10.0 + f64::from(index) * FRAME_SECS);
        }
        // Still high when the cooldown ends: the run starts then, not before.
        assert!(!decider.update(0.9, 12.0));
        assert!(!decider.update(0.9, 13.17) && !decider.update(0.9, 13.25));
        assert!(decider.update(0.9, 13.33));
    }

    #[test]
    fn configured_values_apply() {
        let mut strict = Decider::new(0.95, 5, 0.0);
        assert!(feed(&mut strict, &[0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.0]).is_empty());
        let mut met = Decider::new(0.95, 5, 0.0);
        assert_eq!(feed(&mut met, &[0.96, 0.96, 0.96, 0.96, 0.96, 0.0]), [4]);
    }

    #[test]
    fn reset_forgets_the_run_but_keeps_the_cooldown() {
        let mut decider = decider();
        feed(&mut decider, &[0.9, 0.9]);
        decider.reset();
        assert!(!decider.update(0.9, 101.0));
        assert!(!decider.update(0.9, 101.08));
        assert!(
            decider.update(0.9, 101.16),
            "the run restarted at the frame after the reset"
        );
        let mut cooling = Decider::new(0.8, 1, 3.0);
        assert!(cooling.update(0.9, 50.0));
        cooling.reset();
        assert!(!cooling.update(0.9, 51.0), "the cooldown outlives a reset");
        assert!(cooling.update(0.9, 53.0));
    }

    /// Score-only copy of the owner's recorded takes (`tests/fixtures/wake-scores.json`), with the triggers each rule
    /// gives per level. `cargo test replay_table -- --nocapture` prints the table.
    #[test]
    fn the_recorded_takes_trigger_as_the_fixture_says_at_every_level() {
        let fixture: serde_json::Value =
            serde_json::from_str(include_str!("../../../tests/fixtures/wake-scores.json")).unwrap();
        let takes = fixture["takes"].as_object().unwrap();
        assert_eq!(takes.len(), 29);
        for (name, take) in takes {
            let scores: Vec<f32> = take["scores"]
                .as_array()
                .unwrap()
                .iter()
                .map(|score| score.as_f64().unwrap() as f32)
                .collect();
            for (rule, smoothed) in [("old", false), ("new", true)] {
                for level in [Level::Strict, Level::Balanced, Level::Relaxed] {
                    let (threshold, frames) = level.threshold_and_frames();
                    let mut decider = Decider::new(threshold, frames, DEFAULT_COOLDOWN_SECS)
                        .with_smoothing(smoothed.then(|| level.smoothing()));
                    let name_of_level = format!("{level:?}").to_lowercase();
                    let want: Vec<usize> = take[rule][&name_of_level]
                        .as_array()
                        .unwrap()
                        .iter()
                        .map(|frame| frame.as_u64().unwrap() as usize)
                        .collect();
                    assert_eq!(feed(&mut decider, &scores), want, "{name} {name_of_level} {rule}");
                }
            }
        }
    }

    #[test]
    fn smoothing_gains_the_plain_takes_and_no_run_in_take_triggers() {
        let fixture: serde_json::Value =
            serde_json::from_str(include_str!("../../../tests/fixtures/wake-scores.json")).unwrap();
        let takes = fixture["takes"].as_object().unwrap();
        let triggers = |name: &str, level: &str| takes[name]["new"][level].as_array().unwrap().len();
        for name in ["cortana-03", "cortana-05", "cortana-12"] {
            assert_eq!(triggers(name, "balanced"), 1, "{name}");
        }
        assert_eq!(
            (triggers("cortana-03", "strict"), triggers("cortana-05", "strict")),
            (1, 1)
        );
        for (name, take) in takes {
            for level in ["strict", "balanced", "relaxed"] {
                if name.starts_with("runin-") {
                    assert_eq!(triggers(name, level), 0, "{name} {level}");
                }
                let old = take["old"][level].as_array().unwrap().len();
                assert!(triggers(name, level) >= old, "{name} {level} lost a trigger");
            }
        }
    }

    #[test]
    fn the_levels_map_to_their_numbers() {
        assert_eq!(Level::Strict.threshold_and_frames(), (0.8, 3));
        assert_eq!(Level::Balanced.threshold_and_frames(), (0.7, 3));
        assert_eq!(Level::Relaxed.threshold_and_frames(), (0.6, 3));
        assert_eq!(Level::parse("loud"), None);
    }
}
