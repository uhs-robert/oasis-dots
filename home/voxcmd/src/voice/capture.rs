//! where audio frames come from, shared by the wake listener (80 ms frames) and auto-stop (30 ms): a `pw-record`
//! child, a raw file in tests, or a stream on stdin for `--pcm -`
//!
//! Also the WAV clip and its memfd that both hand to `internal wake-confirm`.
use super::signal;
use std::io::Read;
use std::os::fd::{AsRawFd, FromRawFd};
use std::process::{Child, Command, Stdio};
use std::time::Duration;

/// The tags on the stream's properties. The pause gate's mic check tells voxcmd's own streams from another app's by
/// the `voxcmd.tag` key, so another program using `pw-record` still counts.
pub const WAKE_TAG: &str = "wake";
pub const AUTOSTOP_TAG: &str = "autostop";
pub const SAMPLE_RATE: u32 = 16000;

/// The audio ended: `pw-record` died or was killed, or the file ran out.
#[derive(Debug, PartialEq, Eq)]
pub struct SourceEnded;

pub trait Frames {
    /// A full frame, or None when none came within `timeout` (or a stop was asked for).
    fn next_frame(&mut self, timeout: Duration) -> Result<Option<Vec<i16>>, SourceEnded>;
    /// Releases the source. For `pw-record` that is the microphone, which voxtype records from right after a pause.
    fn close(&mut self);
}

/// Frames cut from a readable descriptor (a pipe), waiting on it and on the stop signal together.
struct FdFrames<R: Read + AsRawFd> {
    reader: R,
    pending: Vec<u8>,
    frame_bytes: usize,
}

impl<R: Read + AsRawFd> FdFrames<R> {
    fn new(reader: R, frame_samples: usize) -> Self {
        Self {
            reader,
            pending: Vec::new(),
            frame_bytes: frame_samples * 2,
        }
    }

    fn frame_from_pending(&mut self) -> Option<Vec<i16>> {
        if self.pending.len() < self.frame_bytes {
            return None;
        }
        let frame = self.pending[..self.frame_bytes]
            .as_chunks::<2>()
            .0
            .iter()
            .map(|pair| i16::from_le_bytes(*pair))
            .collect();
        self.pending.drain(..self.frame_bytes);
        Some(frame)
    }

    fn next_frame(&mut self, timeout: Duration) -> Result<Option<Vec<i16>>, SourceEnded> {
        let deadline = std::time::Instant::now() + timeout;
        while self.pending.len() < self.frame_bytes {
            let left = deadline.saturating_duration_since(std::time::Instant::now());
            let mut fds = [
                libc::pollfd {
                    fd: self.reader.as_raw_fd(),
                    events: libc::POLLIN,
                    revents: 0,
                },
                libc::pollfd {
                    fd: signal::fd(),
                    events: libc::POLLIN,
                    revents: 0,
                },
            ];
            let millis = left.as_millis().min(i32::MAX as u128) as libc::c_int;
            // SAFETY: two valid pollfds; the second is ignored while it is -1.
            let ready = unsafe { libc::poll(fds.as_mut_ptr(), 2, millis) };
            if ready < 0 {
                if std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted {
                    return Ok(None);
                }
                return Err(SourceEnded);
            }
            if fds[1].revents != 0 || ready == 0 {
                return Ok(None);
            }
            let mut chunk = [0u8; 8192];
            match self.reader.read(&mut chunk) {
                Ok(0) => return Err(SourceEnded),
                Ok(read) => self.pending.extend_from_slice(&chunk[..read]),
                Err(error) if error.kind() == std::io::ErrorKind::Interrupted => return Ok(None),
                Err(_) => return Err(SourceEnded),
            }
        }
        Ok(self.frame_from_pending())
    }
}

/// The stream's properties for `pw-record -P`; the wake gate's mic check skips a stream carrying `voxcmd.tag`.
fn stream_properties(tag: &str) -> String {
    format!("{{ voxcmd.tag = \"{tag}\" }}")
}

pub struct PwRecord {
    child: Child,
    frames: FdFrames<std::process::ChildStdout>,
    /// Set once the child was ended and reaped. Its pid is free for the kernel to reuse after that, so a second
    /// `end_child` could signal an unrelated process.
    ended: bool,
}

impl PwRecord {
    /// `tag` is `WAKE_TAG` or `AUTOSTOP_TAG`; frames are `frame_samples` long.
    pub fn spawn(tag: &str, frame_samples: usize) -> std::io::Result<Self> {
        let mut command = Command::new("pw-record");
        command
            .args([
                "-P",
                &stream_properties(tag),
                "--rate",
                "16000",
                "--channels",
                "1",
                "--format",
                "s16",
                "--raw",
                "-",
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        // It goes too when this process is killed without running its cleanup (SIGKILL, an OOM kill).
        crate::process::die_with_parent(&mut command);
        let mut child = command.spawn()?;
        let stdout = child.stdout.take().expect("stdout was piped");
        Ok(Self {
            child,
            frames: FdFrames::new(stdout, frame_samples),
            ended: false,
        })
    }
}

impl Frames for PwRecord {
    fn next_frame(&mut self, timeout: Duration) -> Result<Option<Vec<i16>>, SourceEnded> {
        self.frames.next_frame(timeout)
    }

    fn close(&mut self) {
        self.end();
    }
}

impl PwRecord {
    /// Ends the child once, whether by `close` or by the drop that follows it.
    fn end(&mut self) {
        if !self.ended {
            self.ended = true;
            end_child(&mut self.child);
        }
    }
}

impl Drop for PwRecord {
    fn drop(&mut self) {
        self.end();
    }
}

/// TERM, then KILL after 2 s, and always reaped: no zombie, and the stream is closed when this returns.
fn end_child(child: &mut Child) {
    // SAFETY: signals the child this process spawned and has not yet reaped.
    unsafe { libc::kill(child.id() as libc::pid_t, libc::SIGTERM) };
    let deadline = std::time::Instant::now() + Duration::from_secs(2);
    while std::time::Instant::now() < deadline {
        if matches!(child.try_wait(), Ok(Some(_))) {
            return;
        }
        std::thread::sleep(Duration::from_millis(5));
    }
    let _ = child.kill();
    let _ = child.wait();
}

/// Raw s16 audio streamed on stdin (`--pcm -`): a test feeds it over time. Reads its own copy of descriptor 0, so
/// nothing buffered by `std::io::stdin` hides data from the poll.
pub struct PcmStdin {
    frames: FdFrames<std::fs::File>,
}

impl PcmStdin {
    pub fn new(frame_samples: usize) -> std::io::Result<Self> {
        // SAFETY: a close-on-exec copy of descriptor 0, so a detached check never inherits the feed; the File owns it.
        let fd = unsafe { libc::fcntl(0, libc::F_DUPFD_CLOEXEC, 3) };
        if fd < 0 {
            return Err(std::io::Error::last_os_error());
        }
        // SAFETY: `fd` is a fresh descriptor nothing else owns.
        let file = unsafe { std::fs::File::from_raw_fd(fd) };
        Ok(Self {
            frames: FdFrames::new(file, frame_samples),
        })
    }
}

impl Frames for PcmStdin {
    fn next_frame(&mut self, timeout: Duration) -> Result<Option<Vec<i16>>, SourceEnded> {
        self.frames.next_frame(timeout)
    }

    fn close(&mut self) {}
}

/// A raw s16 little-endian file in frames, for `--pcm` and the tests. A last partial frame is dropped.
pub struct PcmFile {
    samples: Vec<i16>,
    next: usize,
    frame_samples: usize,
}

impl PcmFile {
    pub fn open(path: &std::path::Path, frame_samples: usize) -> std::io::Result<Self> {
        let bytes = std::fs::read(path)?;
        Ok(Self::from_bytes(&bytes, frame_samples))
    }

    pub fn from_bytes(bytes: &[u8], frame_samples: usize) -> Self {
        Self {
            samples: bytes
                .as_chunks::<2>()
                .0
                .iter()
                .map(|pair| i16::from_le_bytes(*pair))
                .collect(),
            next: 0,
            frame_samples,
        }
    }
}

impl Frames for PcmFile {
    fn next_frame(&mut self, _timeout: Duration) -> Result<Option<Vec<i16>>, SourceEnded> {
        let end = self.next + self.frame_samples;
        if end > self.samples.len() {
            return Err(SourceEnded);
        }
        let frame = self.samples[self.next..end].to_vec();
        self.next = end;
        Ok(Some(frame))
    }

    fn close(&mut self) {}
}

/// The frames as a 16 kHz mono s16 WAV file's content.
pub fn wav_bytes<'a>(frames: impl IntoIterator<Item = &'a Vec<i16>>) -> Vec<u8> {
    let pcm: Vec<u8> = frames
        .into_iter()
        .flat_map(|frame| frame.iter().flat_map(|sample| sample.to_le_bytes()))
        .collect();
    let mut wav = Vec::with_capacity(44 + pcm.len());
    wav.extend_from_slice(b"RIFF");
    wav.extend_from_slice(&(36 + pcm.len() as u32).to_le_bytes());
    wav.extend_from_slice(b"WAVEfmt ");
    wav.extend_from_slice(&16u32.to_le_bytes());
    wav.extend_from_slice(&1u16.to_le_bytes());
    wav.extend_from_slice(&1u16.to_le_bytes());
    wav.extend_from_slice(&SAMPLE_RATE.to_le_bytes());
    wav.extend_from_slice(&(SAMPLE_RATE * 2).to_le_bytes());
    wav.extend_from_slice(&2u16.to_le_bytes());
    wav.extend_from_slice(&16u16.to_le_bytes());
    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&(pcm.len() as u32).to_le_bytes());
    wav.extend_from_slice(&pcm);
    wav
}

/// `content` in an anonymous memfd, read from the start: no path another process can open, gone when closed.
pub fn private_audio_file(content: &[u8]) -> std::io::Result<std::fs::File> {
    use std::io::{Seek, Write};
    // SAFETY: memfd_create with a NUL-terminated name; the descriptor it returns is owned by the File.
    let fd = unsafe { libc::memfd_create(c"voxcmd-audio".as_ptr(), libc::MFD_CLOEXEC) };
    if fd < 0 {
        return Err(std::io::Error::last_os_error());
    }
    // SAFETY: `fd` is a fresh descriptor nothing else owns.
    let mut file = unsafe { std::fs::File::from_raw_fd(fd) };
    file.write_all(content)?;
    file.rewind()?;
    Ok(file)
}

#[cfg(test)]
mod tests {
    use super::*;

    const FRAME_SAMPLES: usize = 1280;

    #[test]
    fn both_listeners_tag_their_stream_as_the_wake_gate_expects() {
        assert_eq!(stream_properties(AUTOSTOP_TAG), r#"{ voxcmd.tag = "autostop" }"#);
        assert_eq!(stream_properties(WAKE_TAG), r#"{ voxcmd.tag = "wake" }"#);
    }

    #[test]
    fn a_pcm_file_is_cut_into_whole_frames() {
        let bytes: Vec<u8> = (0..(FRAME_SAMPLES * 2 + 10) as i16)
            .flat_map(i16::to_le_bytes)
            .collect();
        let mut file = PcmFile::from_bytes(&bytes, FRAME_SAMPLES);
        let first = file.next_frame(Duration::ZERO).unwrap().unwrap();
        assert_eq!((first.len(), first[0], first[1279]), (FRAME_SAMPLES, 0, 1279));
        assert_eq!(file.next_frame(Duration::ZERO).unwrap().unwrap()[0], 1280);
        assert_eq!(file.next_frame(Duration::ZERO), Err(SourceEnded));
    }
}
