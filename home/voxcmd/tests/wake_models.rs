//! the model download against a local HTTP server: pinned hashes, a wrong download, a changed file in place
#![allow(dead_code)]

#[path = "../src/voice/wake/models.rs"]
mod models;

use sha2::{Digest, Sha256};
use std::io::{BufRead, BufReader, Write};
use std::net::TcpListener;
use std::sync::{Arc, Mutex};

fn sha(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

/// Serves `/<name>` from `files` and records each path asked for. Runs until the process ends.
fn serve(files: Vec<(&'static str, Vec<u8>)>) -> (String, Arc<Mutex<Vec<String>>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let base = format!("http://{}/", listener.local_addr().unwrap());
    let asked = Arc::new(Mutex::new(Vec::new()));
    let log = Arc::clone(&asked);
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let mut stream = stream.unwrap();
            let mut request_line = String::new();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            reader.read_line(&mut request_line).unwrap();
            let path = request_line.split_whitespace().nth(1).unwrap_or("/").to_string();
            log.lock().unwrap().push(path.clone());
            let body = files
                .iter()
                .find(|(name, _)| format!("/{name}") == path)
                .map(|(_, body)| body);
            let _ = match body {
                Some(body) => write!(
                    stream,
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                    body.len()
                )
                .and_then(|()| stream.write_all(body)),
                None => write!(
                    stream,
                    "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                ),
            };
        }
    });
    (base, asked)
}

const MEL: &[u8] = b"pretend melspectrogram model";
const EMBEDDING: &[u8] = b"pretend embedding model";

fn pins() -> [(&'static str, String); 2] {
    [
        ("melspectrogram.onnx", sha(MEL)),
        ("embedding_model.onnx", sha(EMBEDDING)),
    ]
}

fn run_fetch(dir: &std::path::Path, base: &str, pins: &[(&'static str, String)]) -> Result<Vec<String>, String> {
    let borrowed: Vec<(&str, &str)> = pins.iter().map(|(name, pin)| (*name, pin.as_str())).collect();
    let mut said = Vec::new();
    models::fetch(dir, base, &borrowed, &mut |line| said.push(line.to_string())).map(|()| said)
}

#[test]
fn it_downloads_missing_models_and_skips_verified_ones() {
    let (base, asked) = serve(vec![
        ("melspectrogram.onnx", MEL.to_vec()),
        ("embedding_model.onnx", EMBEDDING.to_vec()),
    ]);
    let dir = tempfile::tempdir().unwrap();
    let cache = dir.path().join("cache/models");
    run_fetch(&cache, &base, &pins()).unwrap();
    assert_eq!(std::fs::read(cache.join("melspectrogram.onnx")).unwrap(), MEL);
    assert_eq!(std::fs::read(cache.join("embedding_model.onnx")).unwrap(), EMBEDDING);
    assert_eq!(asked.lock().unwrap().len(), 2);
    let said = run_fetch(&cache, &base, &pins()).unwrap();
    assert!(said.is_empty(), "{said:?}");
    assert_eq!(asked.lock().unwrap().len(), 2, "a verified file was fetched again");
    assert!(!cache.join("melspectrogram.onnx.part").exists());
}

#[test]
fn a_download_with_the_wrong_hash_is_deleted_and_refused() {
    let (base, _) = serve(vec![
        ("melspectrogram.onnx", b"tampered".to_vec()),
        ("embedding_model.onnx", EMBEDDING.to_vec()),
    ]);
    let dir = tempfile::tempdir().unwrap();
    let error = run_fetch(dir.path(), &base, &pins()).unwrap_err();
    assert!(error.contains("melspectrogram.onnx downloaded with sha256"), "{error}");
    assert!(
        !dir.path().join("melspectrogram.onnx").exists(),
        "the refused file was kept"
    );
    assert!(!dir.path().join("melspectrogram.onnx.part").exists());
    assert!(
        !dir.path().join("embedding_model.onnx").exists(),
        "it went on after a refusal"
    );
}

#[test]
fn a_present_file_with_the_wrong_hash_is_fetched_again() {
    let (base, asked) = serve(vec![
        ("melspectrogram.onnx", MEL.to_vec()),
        ("embedding_model.onnx", EMBEDDING.to_vec()),
    ]);
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(dir.path().join("melspectrogram.onnx"), b"old").unwrap();
    std::fs::write(dir.path().join("embedding_model.onnx"), EMBEDDING).unwrap();
    let said = run_fetch(dir.path(), &base, &pins()).unwrap();
    assert_eq!(std::fs::read(dir.path().join("melspectrogram.onnx")).unwrap(), MEL);
    assert_eq!(*asked.lock().unwrap(), ["/melspectrogram.onnx"]);
    assert!(said[0].contains("does not match the release"), "{said:?}");
}

#[test]
fn a_server_error_is_a_failure_and_leaves_no_partial_file() {
    let (base, _) = serve(vec![]);
    let dir = tempfile::tempdir().unwrap();
    let error = run_fetch(dir.path(), &base, &pins()).unwrap_err();
    assert!(error.contains("curl failed"), "{error}");
    assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 0);
}

#[test]
fn a_start_needs_every_model_present_and_pinned() {
    let dir = tempfile::tempdir().unwrap();
    let wake = dir.path().join("share/cortana.onnx");
    let cache = dir.path().join("cache");
    std::fs::create_dir_all(wake.parent().unwrap()).unwrap();
    std::fs::create_dir_all(&cache).unwrap();
    let features: Vec<(&str, String)> = pins().into_iter().collect();
    let features: Vec<(&str, &str)> = features.iter().map(|(name, pin)| (*name, pin.as_str())).collect();
    let problem = || models::missing_setup(&cache, &wake, &features);
    assert!(problem().unwrap().starts_with("cortana.onnx is not in"));
    std::fs::write(&wake, b"not the model").unwrap();
    assert!(problem().unwrap().contains("is not the tracked model"));
    // The real head, from the tracked file.
    let tracked = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(".local/share/voxcmd/cortana.onnx");
    assert_eq!(models::file_sha256(&tracked).unwrap(), models::WAKE_MODEL_SHA256);
    std::fs::copy(&tracked, &wake).unwrap();
    assert!(problem().unwrap().starts_with("melspectrogram.onnx is not in"));
    std::fs::write(cache.join("melspectrogram.onnx"), b"wrong").unwrap();
    assert!(problem().unwrap().contains("melspectrogram.onnx in") && problem().unwrap().contains("not the pinned"));
    std::fs::write(cache.join("melspectrogram.onnx"), MEL).unwrap();
    std::fs::write(cache.join("embedding_model.onnx"), EMBEDDING).unwrap();
    assert_eq!(problem(), None);
}
