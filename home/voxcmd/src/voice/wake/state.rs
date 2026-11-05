//! `wake.json`, the listener's state for the bar (`VoxWakeState`) and for typing.sh, which reads `pid`
//!
//! `{"state": "armed" | "ready" | "paused", "pid": N, "reason"?: "<pause check>"}`. Self-contained so
//! `tests/wake_state.rs` includes it by path.
use std::path::PathBuf;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    Armed,
    /// The recording a trigger started is under way: the cue to speak.
    Ready,
    Paused,
}

impl State {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Armed => "armed",
            Self::Ready => "ready",
            Self::Paused => "paused",
        }
    }
}

pub struct StateFile {
    path: PathBuf,
    pid: u32,
    last: Option<(State, Option<String>)>,
}

impl StateFile {
    pub fn new(path: PathBuf, pid: u32) -> Self {
        Self { path, pid, last: None }
    }

    /// Writes the state when it or the reason differs from the last write, and always the first time, so the bar sees
    /// a restarted listener. A paused state carries a reason when a pause check paused it, and none when the stream
    /// failed.
    ///
    /// The file is written beside itself and renamed over it: a reader sees the old file or the new one, never half.
    pub fn publish(&mut self, state: State, reason: Option<&str>) -> std::io::Result<()> {
        let now = (state, reason.map(str::to_string));
        if self.last.as_ref() == Some(&now) {
            return Ok(());
        }
        let mut document = serde_json::json!({ "state": state.as_str(), "pid": self.pid });
        if let Some(reason) = reason {
            document["reason"] = reason.into();
        }
        if let Some(dir) = self.path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let partial = self.path.with_extension("json.tmp");
        std::fs::write(&partial, document.to_string())?;
        std::fs::rename(&partial, &self.path)?;
        self.last = Some(now);
        Ok(())
    }
}
