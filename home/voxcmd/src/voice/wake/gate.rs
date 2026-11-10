//! whether the microphone should be left alone, from an ordered list of checks
//!
//! The first check that says pause decides, and `reason` names it. In order: voxtype is recording, a voice session is
//! open, then (when asked for) media is playing and another app is recording. Media and microphone are looked at once a
//! second, and a check that is switched off is not in the list, so its command never runs.
use serde_json::Value;
use std::io::Read;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

/// The tag voxcmd's own recorders carry on their stream (`capture::WAKE_TAG` and `AUTOSTOP_TAG`).
const STREAM_TAG_KEY: &str = "voxcmd.tag";
const SLOW_CHECK_SECS: f64 = 1.0;
const PROBE_TIMEOUT: Duration = Duration::from_secs(3);

pub const VOXTYPE_RECORDING: &str = "voxtype_recording";
pub const SESSION_OPEN: &str = "session_open";
pub const MEDIA_PLAYING: &str = "media_playing";
pub const MIC_IN_USE: &str = "mic_in_use";

pub trait Gate {
    fn paused(&mut self, now: f64) -> bool;
    /// The check that last paused, None when the last look found none.
    fn reason(&self) -> Option<&'static str>;
    fn voxtype_recording(&self) -> bool;
}

struct Slow {
    probe: Box<dyn FnMut() -> bool>,
    verdict: bool,
    next_at: f64,
}

pub struct PauseGate {
    voxtype_state_file: PathBuf,
    session_file: PathBuf,
    proc_dir: PathBuf,
    media: Option<Slow>,
    mic: Option<Slow>,
    reason: Option<&'static str>,
}

impl PauseGate {
    pub fn new(
        voxtype_state_file: PathBuf,
        session_file: PathBuf,
        media_probe: Option<Box<dyn FnMut() -> bool>>,
        mic_probe: Option<Box<dyn FnMut() -> bool>>,
    ) -> Self {
        let slow = |probe| Slow {
            probe,
            verdict: false,
            next_at: f64::NEG_INFINITY,
        };
        Self {
            voxtype_state_file,
            session_file,
            proc_dir: PathBuf::from("/proc"),
            media: media_probe.map(slow),
            mic: mic_probe.map(slow),
            reason: None,
        }
    }

    #[cfg(test)]
    pub fn with_proc_dir(mut self, proc_dir: PathBuf) -> Self {
        self.proc_dir = proc_dir;
        self
    }

    /// Field 22 of `/proc/<pid>/stat`, counted after the last `)` as the session code counts it.
    fn process_start_time(&self, pid: u64) -> Option<String> {
        let stat = std::fs::read_to_string(self.proc_dir.join(pid.to_string()).join("stat")).ok()?;
        stat.rsplit_once(')')?.1.split_whitespace().nth(19).map(str::to_string)
    }

    /// A session file whose owner is alive (the same pid and start time voxcmd checks).
    fn session_open(&self) -> bool {
        let Ok(text) = std::fs::read_to_string(&self.session_file) else {
            return false;
        };
        let Ok(state) = serde_json::from_str::<Value>(&text) else {
            return false;
        };
        let (Some(owner), Some(owner_start)) = (state["owner"].as_u64(), state.get("owner_start")) else {
            return false;
        };
        let owner_start = match owner_start {
            Value::String(text) => text.clone(),
            Value::Number(number) => number.to_string(),
            _ => return false,
        };
        !owner_start.is_empty() && self.process_start_time(owner).as_deref() == Some(owner_start.as_str())
    }
}

fn ask_once_a_second(slow: &mut Option<Slow>, now: f64) -> bool {
    let Some(slow) = slow else { return false };
    if now >= slow.next_at {
        slow.verdict = (slow.probe)();
        slow.next_at = now + SLOW_CHECK_SECS;
    }
    slow.verdict
}

impl Gate for PauseGate {
    fn paused(&mut self, now: f64) -> bool {
        self.reason = if self.voxtype_recording() {
            Some(VOXTYPE_RECORDING)
        } else if self.session_open() {
            Some(SESSION_OPEN)
        } else if ask_once_a_second(&mut self.media, now) {
            Some(MEDIA_PLAYING)
        } else if ask_once_a_second(&mut self.mic, now) {
            Some(MIC_IN_USE)
        } else {
            None
        };
        self.reason.is_some()
    }

    fn reason(&self) -> Option<&'static str> {
        self.reason
    }

    fn voxtype_recording(&self) -> bool {
        std::fs::read_to_string(&self.voxtype_state_file).is_ok_and(|state| state.trim() == "recording")
    }
}

/// Every player: without `--all-players` playerctl reports only the first it finds, which may be a paused browser while
/// another player plays.
pub fn playerctl_playing() -> bool {
    let mut command = Command::new("playerctl");
    command.args(["--all-players", "status"]);
    probe_output(command).is_some_and(|output| output.lines().any(|line| line.trim() == "Playing"))
}

/// Whether some other app holds a capture stream on a real microphone (a call, a recorder), through PipeWire's Pulse
/// interface. Not counted: a stream with voxcmd's tag, voxtype's recording, a stream on a monitor of an output, a corked
/// stream (paused, so nothing is captured). A call muted in its app keeps its stream and counts. Anything that cannot be
/// read means not active.
pub fn other_app_recording() -> bool {
    other_app_recording_from(&mut |args| {
        let mut command = Command::new("pactl");
        command.args(["-f", "json"]).args(args);
        probe_output(command).and_then(|output| serde_json::from_str::<Value>(&output).ok())
    })
}

pub fn other_app_recording_from(pactl: &mut dyn FnMut(&[&str]) -> Option<Value>) -> bool {
    let list = |pactl: &mut dyn FnMut(&[&str]) -> Option<Value>, what: &str| match pactl(&["list", what]) {
        Some(Value::Array(items)) => items,
        _ => Vec::new(),
    };
    let streams: Vec<Value> = list(pactl, "source-outputs")
        .into_iter()
        .filter(|stream| !stream["corked"].as_bool().unwrap_or(false))
        .collect();
    if streams.is_empty() {
        return false;
    }
    let clients = list(pactl, "clients");
    let sources = list(pactl, "sources");
    let is_monitor = |source: &Value| {
        source["name"].as_str().is_some_and(|name| name.ends_with(".monitor"))
            || source["properties"]["device.class"].as_str() == Some("monitor")
    };
    let monitors: Vec<&Value> = sources
        .iter()
        .filter(|source| is_monitor(source))
        .map(|source| &source["index"])
        .collect();
    streams.iter().any(|stream| {
        let mut properties = clients
            .iter()
            .find(|client| {
                client["index"].to_string().trim_matches('"') == stream["client"].to_string().trim_matches('"')
            })
            .and_then(|client| client["properties"].as_object().cloned())
            .unwrap_or_default();
        if let Some(own) = stream["properties"].as_object() {
            properties.extend(own.clone());
        }
        let is_voxtype = ["application.process.binary", "application.name"].iter().any(|key| {
            properties
                .get(*key)
                .and_then(Value::as_str)
                .is_some_and(|name| name.to_lowercase().contains("voxtype"))
        });
        let on_monitor = !stream["source"].is_null() && monitors.contains(&&stream["source"]);
        !(on_monitor || is_voxtype || properties.contains_key(STREAM_TAG_KEY))
    })
}

/// A command's stdout when it exits 0 within `PROBE_TIMEOUT`, else None. Not `process::run_with_timeout`: that installs
/// the signal handlers which end voxcmd by re-raising the signal, and the listener stops itself instead.
fn probe_output(mut command: Command) -> Option<String> {
    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    let mut child = command.spawn().ok()?;
    let mut stdout = child.stdout.take()?;
    let reader = std::thread::spawn(move || {
        let mut text = String::new();
        let _ = stdout.read_to_string(&mut text);
        text
    });
    let deadline = Instant::now() + PROBE_TIMEOUT;
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Some(status),
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(10)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                break None;
            }
        }
    };
    let text = reader.join().ok()?;
    status.filter(|status| status.success()).map(|_| text)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::cell::RefCell;
    use std::rc::Rc;

    fn mic(source_outputs: Value, clients: Value, sources: Value) -> bool {
        other_app_recording_from(&mut |args| match args[1] {
            "source-outputs" => Some(source_outputs.clone()),
            "clients" => Some(clients.clone()),
            "sources" => Some(sources.clone()),
            _ => None,
        })
    }

    fn microphone() -> Value {
        json!([{ "index": 1, "name": "alsa_input.usb-mic", "properties": {} }, { "index": 2, "name": "alsa_output.x.monitor", "properties": {} }])
    }

    #[test]
    fn the_listeners_own_tagged_stream_is_not_active() {
        let streams = json!([{ "source": 1, "client": 7, "properties": { "voxcmd.tag": "wake" } }]);
        assert!(!mic(streams, json!([]), microphone()));
    }

    #[test]
    fn firefox_an_untagged_pw_record_and_a_tag_on_the_client_alone() {
        let firefox = json!([{ "source": 1, "client": 7, "properties": { "application.name": "Firefox" } }]);
        assert!(mic(firefox.clone(), json!([]), microphone()));
        let tagged_client = json!([{ "index": 7, "properties": { "voxcmd.tag": "autostop" } }]);
        assert!(!mic(firefox, tagged_client, microphone()));
    }

    #[test]
    fn voxtype_monitors_and_corked_streams_are_excluded() {
        let voxtype = json!([{ "source": 1, "client": 7, "properties": { "application.name": "Voxtype" } }]);
        assert!(!mic(voxtype, json!([]), microphone()));
        let client_voxtype =
            json!([{ "index": 7, "properties": { "application.process.binary": "/usr/bin/voxtype" } }]);
        assert!(!mic(
            json!([{ "source": 1, "client": 7, "properties": {} }]),
            client_voxtype,
            microphone()
        ));
        let on_monitor = json!([{ "source": 2, "client": 7, "properties": {} }]);
        assert!(!mic(on_monitor, json!([]), microphone()));
        let corked = json!([{ "source": 1, "client": 7, "corked": true, "properties": {} }]);
        assert!(!mic(corked, json!([]), microphone()));
    }

    #[test]
    fn one_counting_stream_among_excluded_ones_is_enough() {
        let streams = json!([
            { "source": 1, "client": 7, "properties": { "voxcmd.tag": "wake" } },
            { "source": 1, "client": 8, "properties": { "application.name": "zoom" } }
        ]);
        assert!(mic(streams, json!([]), microphone()));
    }

    #[test]
    fn a_missing_or_failing_pactl_is_not_active() {
        assert!(!other_app_recording_from(&mut |_| None));
        assert!(!mic(json!("garbage"), json!(null), json!(3)));
    }

    fn gate_in(dir: &std::path::Path) -> PauseGate {
        PauseGate::new(dir.join("state"), dir.join("session.json"), None, None).with_proc_dir(dir.join("proc"))
    }

    #[test]
    fn voxtype_recording_pauses_and_other_states_do_not() {
        let dir = tempfile::tempdir().unwrap();
        let mut gate = gate_in(dir.path());
        assert!(!gate.paused(0.0), "no state file is idle");
        for (state, paused) in [
            ("recording\n", true),
            ("idle\n", false),
            ("transcribing\n", false),
            ("", false),
        ] {
            std::fs::write(dir.path().join("state"), state).unwrap();
            assert_eq!(gate.paused(0.0), paused, "{state:?}");
        }
        std::fs::write(dir.path().join("state"), "recording\n").unwrap();
        assert!(gate.paused(0.0));
        assert_eq!(gate.reason(), Some(VOXTYPE_RECORDING));
    }

    #[test]
    fn a_session_pauses_only_while_its_owner_lives() {
        let dir = tempfile::tempdir().unwrap();
        let mut gate = gate_in(dir.path());
        let session = dir.path().join("session.json");
        // /proc/<pid>/stat: the name may hold spaces and parens, so fields count after the last ")".
        let stat = "321 (a (b) c) S 1 1 1 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 98765 0 0";
        std::fs::create_dir_all(dir.path().join("proc/321")).unwrap();
        std::fs::write(dir.path().join("proc/321/stat"), stat).unwrap();
        std::fs::write(&session, r#"{"owner": 321, "owner_start": "98765"}"#).unwrap();
        assert!(gate.paused(0.0));
        assert_eq!(gate.reason(), Some(SESSION_OPEN));
        std::fs::write(&session, r#"{"owner": 321, "owner_start": 98765}"#).unwrap();
        assert!(gate.paused(0.0), "a numeric start time counts");
        std::fs::write(&session, r#"{"owner": 321, "owner_start": "11111"}"#).unwrap();
        assert!(!gate.paused(0.0), "a reused pid has another start time");
        std::fs::write(&session, r#"{"owner": 999, "owner_start": "98765"}"#).unwrap();
        assert!(!gate.paused(0.0), "a dead owner");
        std::fs::write(&session, "{not json").unwrap();
        assert!(!gate.paused(0.0), "an unreadable file");
        assert_eq!(gate.reason(), None);
    }

    #[test]
    fn slow_checks_are_asked_once_a_second_and_after_the_first_two() {
        let dir = tempfile::tempdir().unwrap();
        let asked = Rc::new(RefCell::new(Vec::new()));
        let media_log = Rc::clone(&asked);
        let mic_log = Rc::clone(&asked);
        let mut gate = PauseGate::new(
            dir.path().join("state"),
            dir.path().join("session.json"),
            Some(Box::new(move || {
                media_log.borrow_mut().push("media");
                false
            })),
            Some(Box::new(move || {
                mic_log.borrow_mut().push("mic");
                true
            })),
        );
        assert!(gate.paused(0.0));
        assert_eq!(gate.reason(), Some(MIC_IN_USE));
        for now in [0.3, 0.6, 0.9] {
            assert!(gate.paused(now));
        }
        assert_eq!(*asked.borrow(), ["media", "mic"], "asked again inside a second");
        assert!(gate.paused(1.0));
        assert_eq!(asked.borrow().len(), 4);
        std::fs::write(dir.path().join("state"), "recording").unwrap();
        assert!(gate.paused(5.0));
        assert_eq!(gate.reason(), Some(VOXTYPE_RECORDING));
        assert_eq!(asked.borrow().len(), 4, "a check after a pause is not asked");
    }

    #[test]
    fn a_switched_off_check_never_runs() {
        let dir = tempfile::tempdir().unwrap();
        let mut gate = gate_in(dir.path());
        assert!(!gate.paused(0.0) && gate.reason().is_none());
    }
}
