//! frame scores to triggers: a score held high for enough frames, then a cooldown
//!
//! Times are seconds on any monotonic clock, passed in, so tests drive it with a fake one.

pub const DEFAULT_COOLDOWN_SECS: f64 = 3.0;

/// A named sensitivity of the cortana model. The numbers come from 20 recorded takes at 3 frames (all trigger from 0.5
/// to 0.75, 19 at 0.8, 18 at 0.9). Whisper confirms every trigger, so a false one costs a transcription, and strict keeps
/// those down (74 in 3.2 h of everyday audio at 0.8). Balanced and relaxed sit inside the band where every take triggered.
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

    /// The score a frame needs and the consecutive frames that need it.
    pub fn threshold_and_frames(self) -> (f32, u32) {
        match self {
            Self::Strict => (0.8, 3),
            Self::Balanced => (0.7, 3),
            Self::Relaxed => (0.6, 3),
        }
    }
}

pub struct Decider {
    threshold: f32,
    frames: u32,
    cooldown_secs: f64,
    run: u32,
    cooldown_until: f64,
}

impl Decider {
    pub fn new(threshold: f32, frames: u32, cooldown_secs: f64) -> Self {
        Self {
            threshold,
            frames,
            cooldown_secs,
            run: 0,
            cooldown_until: f64::NEG_INFINITY,
        }
    }

    /// Forgets a phrase under way (the stream closed). The cooldown stays: a pause must not let a second trigger in.
    pub fn reset(&mut self) {
        self.run = 0;
    }

    /// True once, on the frame that completes the hold. That is near the end of the word, which the listener then has
    /// confirmed before anything starts. Scores during the cooldown are ignored, and do not build a run.
    pub fn update(&mut self, score: f32, now: f64) -> bool {
        if now < self.cooldown_until {
            return false;
        }
        self.run = if score >= self.threshold { self.run + 1 } else { 0 };
        if self.run < self.frames {
            return false;
        }
        self.reset();
        self.cooldown_until = now + self.cooldown_secs;
        true
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
    fn two_frames_are_not_enough() {
        assert!(feed(&mut decider(), &[0.9, 0.95, 0.1, 0.0]).is_empty());
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

    #[test]
    fn the_levels_map_to_their_numbers() {
        assert_eq!(Level::Strict.threshold_and_frames(), (0.8, 3));
        assert_eq!(Level::Balanced.threshold_and_frames(), (0.7, 3));
        assert_eq!(Level::Relaxed.threshold_and_frames(), (0.6, 3));
        assert_eq!(Level::parse("loud"), None);
    }
}
