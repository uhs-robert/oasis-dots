//! routing a phrase: verb patterns, matching, near misses, and the `explain` trace
//!
//! 2.2a has the match layer only; resolving matches into options (hooks), the tiers' decision, correction retries and
//! sequences come in 2.2b (router.rs, resolve.rs, sequence.rs).
pub mod matcher;
pub mod near_miss;
pub mod pattern;
pub mod trace;

#[cfg(test)]
mod goldens;
