//! voxtype's state file, as auto-stop watches it
use std::path::PathBuf;
use std::time::{Duration, Instant};

/// How long voxtype gets to report the recording it was asked to start.
const START_GRACE: Duration = Duration::from_secs(3);

/// Once its recording has been seen, anything else means it ended.
pub struct RecordingState {
    path: PathBuf,
    started_at: Instant,
    recording_seen: bool,
}

impl RecordingState {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            started_at: Instant::now(),
            recording_seen: false,
        }
    }

    pub fn ended(&mut self) -> bool {
        let state =
            std::fs::read_to_string(&self.path).map_or_else(|_| "idle".to_string(), |text| text.trim().to_string());
        if state == "recording" {
            self.recording_seen = true;
            return false;
        }
        self.recording_seen || self.started_at.elapsed() > START_GRACE
    }
}
