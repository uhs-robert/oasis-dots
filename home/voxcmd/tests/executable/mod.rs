//! Writing a stub script that a test then runs.
use std::io::Write;
use std::path::Path;
use std::process::Command;

/// Writes `script` to `path` as an executable through `install`, so this process never holds a write fd on it. Such an
/// fd is inherited by any child another test thread forks meanwhile, and until that child execs, running the script
/// fails with ETXTBSY. Writing elsewhere and renaming into place does not help: the inode is the same.
pub fn write_executable(path: &Path, script: &str) {
    let mut source = tempfile::NamedTempFile::new().unwrap();
    source.write_all(script.as_bytes()).unwrap();
    let status = Command::new("install")
        .arg("-m755")
        .arg(source.path())
        .arg(path)
        .status()
        .unwrap();
    assert!(status.success(), "install {}", path.display());
}
