//! `wake.json`: written on a change only, always the first time, and never seen half-written
#![allow(dead_code)]

#[path = "../src/voice/wake/state.rs"]
mod state;

use state::{State, StateFile};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

fn read(path: &std::path::Path) -> serde_json::Value {
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

#[test]
fn the_first_write_holds_the_pid_and_the_state() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("run/voxcmd/wake.json");
    let mut file = StateFile::new(path.clone(), 4242);
    file.publish(State::Armed, None).unwrap();
    assert_eq!(read(&path), serde_json::json!({ "state": "armed", "pid": 4242 }));
}

#[test]
fn a_paused_state_carries_its_reason_and_resuming_drops_it() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wake.json");
    let mut file = StateFile::new(path.clone(), 1);
    file.publish(State::Paused, Some("voxtype_recording")).unwrap();
    assert_eq!(read(&path)["reason"], "voxtype_recording");
    file.publish(State::Armed, None).unwrap();
    assert_eq!(read(&path), serde_json::json!({ "state": "armed", "pid": 1 }));
}

#[test]
fn the_file_is_rewritten_only_when_the_state_or_reason_changes() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wake.json");
    let mut file = StateFile::new(path.clone(), 1);
    file.publish(State::Armed, None).unwrap();
    // A rewrite would give the file a new inode, which a rename always does.
    let inode = || std::os::unix::fs::MetadataExt::ino(&std::fs::metadata(&path).unwrap());
    let first = inode();
    file.publish(State::Armed, None).unwrap();
    assert_eq!(inode(), first, "the same state again rewrote the file");
    file.publish(State::Paused, Some("session_open")).unwrap();
    let second = inode();
    assert_ne!(second, first);
    file.publish(State::Paused, Some("session_open")).unwrap();
    assert_eq!(inode(), second);
    file.publish(State::Paused, Some("mic_in_use")).unwrap();
    assert_ne!(inode(), second, "a new reason under the same state is a change");
}

#[test]
fn a_restarted_listener_writes_even_when_the_file_already_says_the_same() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wake.json");
    StateFile::new(path.clone(), 1).publish(State::Armed, None).unwrap();
    StateFile::new(path.clone(), 2).publish(State::Armed, None).unwrap();
    assert_eq!(read(&path)["pid"], 2);
}

#[test]
fn a_failed_write_is_tried_again_by_the_next_publish() {
    let dir = tempfile::tempdir().unwrap();
    let blocker = dir.path().join("blocked");
    std::fs::write(&blocker, "").unwrap();
    let mut file = StateFile::new(blocker.join("wake.json"), 1);
    assert!(file.publish(State::Armed, None).is_err());
    assert!(
        file.publish(State::Armed, None).is_err(),
        "the failure was remembered as a write"
    );
}

#[test]
fn readers_never_see_a_partial_file_while_it_is_rewritten() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wake.json");
    let mut file = StateFile::new(path.clone(), 77);
    file.publish(State::Armed, None).unwrap();
    let done = AtomicBool::new(false);
    let reads = std::thread::scope(|scope| {
        let readers: Vec<_> = (0..4)
            .map(|_| {
                scope.spawn(|| {
                    let mut reads = 0u32;
                    while !done.load(Ordering::Relaxed) {
                        let text = std::fs::read_to_string(&path).expect("the file vanished mid-rewrite");
                        let value: serde_json::Value = serde_json::from_str(&text)
                            .unwrap_or_else(|error| panic!("partial read {text:?}: {error}"));
                        assert_eq!(value["pid"], 77, "{text}");
                        assert!(
                            ["armed", "ready", "paused"].contains(&value["state"].as_str().unwrap()),
                            "{text}"
                        );
                        reads += 1;
                    }
                    reads
                })
            })
            .collect();
        let deadline = Instant::now() + Duration::from_millis(1500);
        let reasons = ["voxtype_recording", "session_open", "media_playing", "mic_in_use"];
        let mut round = 0usize;
        while Instant::now() < deadline {
            let (state, reason) = match round % 3 {
                0 => (State::Armed, None),
                1 => (State::Ready, None),
                _ => (State::Paused, Some(reasons[round % reasons.len()])),
            };
            file.publish(state, reason).unwrap();
            round += 1;
        }
        done.store(true, Ordering::Relaxed);
        readers.into_iter().map(|reader| reader.join().unwrap()).sum::<u32>()
    });
    assert!(reads > 100, "the readers barely ran: {reads} reads");
}
