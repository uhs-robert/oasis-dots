//! where the 80 ms frames come from: a `pw-record` child, or a raw file in tests
use super::scorer::FRAME_SAMPLES;
use super::signal;
use std::io::Read;
use std::os::fd::AsRawFd;
use std::process::{Child, Command, Stdio};
use std::time::Duration;

/// The tag on the stream's properties. The pause gate's mic check tells the listener's own stream (and
/// voxcmd-autostop's) from another app's by it, so another program using `pw-record` still counts.
pub const STREAM_TAG: &str = "{ voxcmd.tag = \"wake\" }";
pub const SAMPLE_RATE: u32 = 16000;
const FRAME_BYTES: usize = FRAME_SAMPLES * 2;

/// The audio ended: `pw-record` died or was killed, or the file ran out.
#[derive(Debug, PartialEq, Eq)]
pub struct SourceEnded;

pub trait Frames {
    /// A full frame, or None when none came within `timeout` (or a stop was asked for).
    fn next_frame(&mut self, timeout: Duration) -> Result<Option<Vec<i16>>, SourceEnded>;
    /// Releases the source. For `pw-record` that is the microphone, which voxtype records from right after a pause.
    fn close(&mut self);
}

pub struct PwRecord {
    child: Child,
    pending: Vec<u8>,
    /// Set once the child was ended and reaped. Its pid is free for the kernel to reuse after that, so a second
    /// `end_child` could signal an unrelated process.
    ended: bool,
}

impl PwRecord {
    pub fn spawn() -> std::io::Result<Self> {
        let mut command = Command::new("pw-record");
        command
            .args([
                "-P",
                STREAM_TAG,
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
        Ok(Self {
            child: command.spawn()?,
            pending: Vec::new(),
            ended: false,
        })
    }

    fn frame_from_pending(&mut self) -> Option<Vec<i16>> {
        if self.pending.len() < FRAME_BYTES {
            return None;
        }
        let frame = self.pending[..FRAME_BYTES]
            .as_chunks::<2>()
            .0
            .iter()
            .map(|pair| i16::from_le_bytes(*pair))
            .collect();
        self.pending.drain(..FRAME_BYTES);
        Some(frame)
    }
}

impl Frames for PwRecord {
    fn next_frame(&mut self, timeout: Duration) -> Result<Option<Vec<i16>>, SourceEnded> {
        let deadline = std::time::Instant::now() + timeout;
        while self.pending.len() < FRAME_BYTES {
            let left = deadline.saturating_duration_since(std::time::Instant::now());
            let stdout = self.child.stdout.as_mut().ok_or(SourceEnded)?;
            let mut fds = [
                libc::pollfd {
                    fd: stdout.as_raw_fd(),
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
            match stdout.read(&mut chunk) {
                Ok(0) => return Err(SourceEnded),
                Ok(read) => self.pending.extend_from_slice(&chunk[..read]),
                Err(error) if error.kind() == std::io::ErrorKind::Interrupted => return Ok(None),
                Err(_) => return Err(SourceEnded),
            }
        }
        Ok(self.frame_from_pending())
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

/// A raw s16 little-endian file in frames, for `--pcm` and the tests. A last partial frame is dropped.
pub struct PcmFile {
    samples: Vec<i16>,
    next: usize,
}

impl PcmFile {
    pub fn open(path: &std::path::Path) -> std::io::Result<Self> {
        let bytes = std::fs::read(path)?;
        Ok(Self::from_bytes(&bytes))
    }

    pub fn from_bytes(bytes: &[u8]) -> Self {
        Self {
            samples: bytes
                .as_chunks::<2>()
                .0
                .iter()
                .map(|pair| i16::from_le_bytes(*pair))
                .collect(),
            next: 0,
        }
    }
}

impl Frames for PcmFile {
    fn next_frame(&mut self, _timeout: Duration) -> Result<Option<Vec<i16>>, SourceEnded> {
        let end = self.next + FRAME_SAMPLES;
        if end > self.samples.len() {
            return Err(SourceEnded);
        }
        let frame = self.samples[self.next..end].to_vec();
        self.next = end;
        Ok(Some(frame))
    }

    fn close(&mut self) {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pcm_file_is_cut_into_whole_frames() {
        let bytes: Vec<u8> = (0..(FRAME_SAMPLES * 2 + 10) as i16)
            .flat_map(i16::to_le_bytes)
            .collect();
        let mut file = PcmFile::from_bytes(&bytes);
        let first = file.next_frame(Duration::ZERO).unwrap().unwrap();
        assert_eq!((first.len(), first[0], first[1279]), (FRAME_SAMPLES, 0, 1279));
        assert_eq!(file.next_frame(Duration::ZERO).unwrap().unwrap()[0], 1280);
        assert_eq!(file.next_frame(Duration::ZERO), Err(SourceEnded));
    }
}
