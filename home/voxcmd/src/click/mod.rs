//! Click: the port of `click-match.awk` (the matcher) and, in later items, of `click-ocr` and click.sh. The awk's
//! function names are kept in snake_case so the two read side by side.
#[cfg(test)]
mod goldens;
pub mod internal;
pub mod matcher;
pub mod ocr_format;
pub mod words;
