//! routing a phrase: verb patterns, matching, near misses, resolving matches into options, the tiers, sequences, and
//! the `explain` trace
pub mod matcher;
pub mod near_miss;
pub mod pattern;
pub mod resolve;
pub mod router;
pub mod runner;
pub mod sequence;
pub mod sequence_run;
pub mod trace;

#[cfg(test)]
mod goldens;
#[cfg(test)]
mod scenarios;
