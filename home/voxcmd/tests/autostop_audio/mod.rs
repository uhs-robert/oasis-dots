//! synthetic audio for the auto-stop tests, shared by `autostop.rs` and `autostop_parity.rs`
//!
//! `noise:<secs>:<dBFS>` is a steady hiss (a fan) and `voice:<secs>:<dBFS>` a syllable-paced tone over the last noise.
//! The generator is deterministic, so the parity goldens (made by the Python detector on this exact audio) stay valid.
#![allow(dead_code)]

const RATE: f64 = 16000.0;

pub fn pcm(segments: &[&str]) -> Vec<u8> {
    let mut state = 0x2545_f491_4f6c_dd1d_u64;
    let mut uniform = move || {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        (state >> 11) as f64 / (1u64 << 53) as f64 * 2.0 - 1.0
    };
    let mut samples: Vec<i16> = Vec::new();
    let mut room_db = -90.0;
    for segment in segments {
        let mut parts = segment.split(':');
        let (kind, secs, db) = (
            parts.next().unwrap(),
            parts.next().unwrap().parse::<f64>().unwrap(),
            parts.next().unwrap().parse::<f64>().unwrap(),
        );
        let count = (secs * RATE) as usize;
        let amplitude = 32768.0 * 10f64.powf(db / 20.0);
        if kind == "noise" {
            room_db = db;
            samples.extend((0..count).map(|_| (uniform() * amplitude * 3f64.sqrt()) as i16));
        } else {
            let room_amplitude = 32768.0 * 10f64.powf(room_db / 20.0);
            samples.extend((0..count).map(|i| {
                let i = i as f64;
                let voice = amplitude
                    * 2f64.sqrt()
                    * (std::f64::consts::PI * 4.0 * i / RATE).sin().abs()
                    * (2.0 * std::f64::consts::PI * 180.0 * i / RATE).sin();
                (uniform() * room_amplitude * 3f64.sqrt() + voice).clamp(-32768.0, 32767.0) as i16
            }));
        }
    }
    samples.iter().flat_map(|sample| sample.to_le_bytes()).collect()
}

/// The clips the parity goldens cover, by name.
pub const CLIPS: [(&str, &[&str]); 11] = [
    ("fan-after-quiet-start", &["noise:0.3:-75", "noise:7.7:-42"]),
    (
        "word-over-fan",
        &["noise:0.3:-75", "noise:2.7:-42", "voice:0.9:-18", "noise:4:-42"],
    ),
    (
        "knocks",
        &[
            "noise:1:-55",
            "voice:0.15:-25",
            "noise:0.35:-55",
            "voice:0.15:-25",
            "noise:5:-55",
        ],
    ),
    ("short-word", &["noise:2:-48", "voice:0.15:-28", "noise:6:-48"]),
    ("word-at-deadline", &["noise:5.8:-48", "voice:0.5:-28", "noise:3:-48"]),
    ("long-speech", &["noise:0.3:-60", "voice:9:-18", "noise:3:-60"]),
    ("quiet-room", &["noise:6:-60"]),
    ("talk-in-quiet", &["noise:3:-55", "voice:4:-18", "noise:3:-55"]),
    ("word-then-quiet", &["noise:2:-55", "voice:1:-18", "noise:2:-55"]),
    (
        "two-words",
        &[
            "noise:1:-50",
            "voice:0.8:-20",
            "noise:0.8:-50",
            "voice:0.8:-20",
            "noise:3:-50",
        ],
    ),
    ("loud-room", &["noise:3:-30", "voice:1:-10", "noise:3:-30"]),
];

/// The settings profiles the goldens were made with.
pub const PROFILES: [(&str, &[(&str, &str)]); 5] = [
    ("command", &[]),
    (
        "session",
        &[
            ("VOXCMD_AUTOSTOP_MIN_SPEECH_SECS", "0.4"),
            ("VOXCMD_AUTOSTOP_SILENCE_SECS", "1.5"),
            ("VOXCMD_AUTOSTOP_NO_SPEECH_SECS", "5"),
        ],
    ),
    ("reply", &[("VOXCMD_AUTOSTOP_MIN_SPEECH_SECS", "0.1")]),
    (
        "type",
        &[
            ("VOXCMD_AUTOSTOP_MAX_SECS", "4"),
            ("VOXCMD_AUTOSTOP_SILENCE_SECS", "0.5"),
        ],
    ),
    ("fixed", &[("VOXCMD_AUTOSTOP_THRESHOLD_DB", "-35")]),
];
