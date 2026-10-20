//! Click: the port of `click-match.awk` (the matcher), of `click-ocr` (capture and OCR) and of click.sh (the `screen_text`
//! provider and the click itself). The awk's
//! function names are kept in snake_case so the two read side by side.
pub mod act;
pub mod bridge_map;
pub mod capture;
pub mod covering;
pub mod driver;
#[cfg(test)]
mod goldens;
pub mod internal;
pub mod matcher;
pub mod ocr;
pub mod ocr_format;
#[cfg(test)]
mod ocr_goldens;
pub mod pick;
pub mod provider;
pub mod strips;
pub mod target_file;
pub mod words;
