//! SIGTERM and SIGINT as a flag plus a pipe, so the loop notices a stop at once, even in the middle of a wait
//!
//! Not `process`'s handlers: those end voxcmd by re-raising the signal, but the wake unit expects the listener to stop
//! itself and exit 0 after it has killed its `pw-record`, and the watcher expects auto-stop to exit 4 (nothing to do)
//! the same way. Shared by both; the exit code is the caller's.
use std::os::fd::RawFd;
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::time::Duration;

static REQUESTED: AtomicBool = AtomicBool::new(false);
static WRITE_END: AtomicI32 = AtomicI32::new(-1);
static READ_END: AtomicI32 = AtomicI32::new(-1);

extern "C" fn on_signal(_signal: libc::c_int) {
    REQUESTED.store(true, Ordering::SeqCst);
    let write_end = WRITE_END.load(Ordering::SeqCst);
    if write_end >= 0 {
        // SAFETY: write is async-signal-safe. A full pipe already holds a wake-up, so the result is ignored.
        unsafe { libc::write(write_end, [1u8].as_ptr().cast(), 1) };
    }
}

pub fn install() -> std::io::Result<()> {
    install_for(&[libc::SIGTERM, libc::SIGINT])
}

/// The same for another set of signals (auto-stop also stops on SIGHUP).
pub fn install_for(signals: &[libc::c_int]) -> std::io::Result<()> {
    let mut ends = [0; 2];
    // SAFETY: `ends` holds the two descriptors pipe2 fills in.
    if unsafe { libc::pipe2(ends.as_mut_ptr(), libc::O_CLOEXEC | libc::O_NONBLOCK) } != 0 {
        return Err(std::io::Error::last_os_error());
    }
    READ_END.store(ends[0], Ordering::SeqCst);
    WRITE_END.store(ends[1], Ordering::SeqCst);
    for &signal in signals {
        // SAFETY: a zeroed sigaction with only the handler set; no SA_RESTART, so a blocked read returns early.
        unsafe {
            let mut action: libc::sigaction = std::mem::zeroed();
            action.sa_sigaction = on_signal as extern "C" fn(libc::c_int) as libc::sighandler_t;
            libc::sigemptyset(&raw mut action.sa_mask);
            if libc::sigaction(signal, &raw const action, std::ptr::null_mut()) != 0 {
                return Err(std::io::Error::last_os_error());
            }
        }
    }
    Ok(())
}

pub fn requested() -> bool {
    REQUESTED.load(Ordering::SeqCst)
}

/// The read end, readable once a stop was asked for; -1 before `install`.
pub fn fd() -> RawFd {
    READ_END.load(Ordering::SeqCst)
}

/// Waits for `duration`, or until a stop is asked for.
pub fn sleep(duration: Duration) {
    let mut fds = [libc::pollfd {
        fd: fd(),
        events: libc::POLLIN,
        revents: 0,
    }];
    let millis = duration.as_millis().min(i32::MAX as u128) as libc::c_int;
    // SAFETY: one valid pollfd; a negative fd is ignored by poll, so before `install` this is a plain sleep.
    unsafe { libc::poll(fds.as_mut_ptr(), 1, millis) };
}
