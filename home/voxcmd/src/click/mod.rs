//! Click: the port of `click-match.awk` (the matcher), of `click-ocr` (capture and OCR) and, in a later item, of click.sh. The awk's
//! function names are kept in snake_case so the two read side by side.
pub mod capture;
pub mod driver;
#[cfg(test)]
mod goldens;
pub mod internal;
pub mod matcher;
pub mod ocr;
pub mod ocr_format;
#[cfg(test)]
mod ocr_goldens;
pub mod strips;
pub mod target_file;
pub mod words;
