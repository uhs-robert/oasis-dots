//! frame scores for the wake word: openWakeWord's mel, embedding and head models run on tract
//!
//! Self-contained (no `crate::` imports) so `tests/wake_scorer.rs` includes this file by path and runs it on a clip.
use std::path::Path;
use std::sync::Arc;
use tract_onnx::prelude::*;

/// openWakeWord scores audio in multiples of 80 ms.
pub const FRAME_SAMPLES: usize = 1280;

/// The mel model sees each frame with this much of the audio before it.
const MEL_CONTEXT_SAMPLES: usize = 480;
const MEL_BINS: usize = 32;
/// Mel rows one embedding looks at.
const MEL_WINDOW_ROWS: usize = 76;
const EMBEDDING_SIZE: usize = 96;
/// Embeddings the head looks at.
const HEAD_WINDOW: usize = 16;
/// openWakeWord scores zero for the first frames after a reset while its buffers fill.
const WARMUP_FRAMES: usize = 5;

/// The head's window right after a reset. openWakeWord fills it with the embedding of random noise, which differs per
/// start; this is one such draw (the spike's), so the first 16 frames after a reset score the same every time.
const INITIAL_FEATURES: &[u8] = include_bytes!("init_features.f32");

pub trait Scorer {
    /// The wake word's score for the next 80 ms frame, 0 to 1.
    fn score(&mut self, frame: &[i16]) -> f32;
    /// Forgets the audio so far, as a closed stream does.
    fn reset(&mut self);
}

type Plan = Arc<TypedSimplePlan>;

pub struct TractScorer {
    /// The first frame has no context yet, so it is a shape of its own.
    mel_first: Plan,
    mel_steady: Plan,
    embedding: Plan,
    head: Plan,
    context: Vec<f32>,
    mel_rows: Vec<f32>,
    features: Vec<f32>,
    frames_seen: usize,
}

impl TractScorer {
    pub fn load(feature_dir: &Path, wake_model: &Path) -> Result<Self, String> {
        let mel = feature_dir.join("melspectrogram.onnx");
        let mut scorer = Self {
            mel_first: load_plan(&mel, &[1, FRAME_SAMPLES])?,
            mel_steady: load_plan(&mel, &[1, FRAME_SAMPLES + MEL_CONTEXT_SAMPLES])?,
            embedding: load_plan(
                &feature_dir.join("embedding_model.onnx"),
                &[1, MEL_WINDOW_ROWS, MEL_BINS, 1],
            )?,
            head: load_plan(wake_model, &[1, HEAD_WINDOW, EMBEDDING_SIZE])?,
            context: Vec::new(),
            mel_rows: Vec::new(),
            features: Vec::new(),
            frames_seen: 0,
        };
        scorer.reset();
        Ok(scorer)
    }

    fn try_score(&mut self, frame: &[i16]) -> TractResult<f32> {
        let mut segment = std::mem::take(&mut self.context);
        segment.extend(frame.iter().map(|&sample| f32::from(sample)));
        let mel_plan = if segment.len() == FRAME_SAMPLES {
            &self.mel_first
        } else {
            &self.mel_steady
        };
        let mel = run(mel_plan, &[1, segment.len()], segment.clone())?;
        self.mel_rows.extend(mel.iter().map(|value| value / 10.0 + 2.0));
        keep_last(&mut self.mel_rows, MEL_WINDOW_ROWS * MEL_BINS);
        let embedding = run(
            &self.embedding,
            &[1, MEL_WINDOW_ROWS, MEL_BINS, 1],
            self.mel_rows.clone(),
        )?;
        self.features.extend_from_slice(&embedding);
        keep_last(&mut self.features, HEAD_WINDOW * EMBEDDING_SIZE);
        let score = run(&self.head, &[1, HEAD_WINDOW, EMBEDDING_SIZE], self.features.clone())?[0];
        keep_last(&mut segment, MEL_CONTEXT_SAMPLES);
        self.context = segment;
        self.frames_seen += 1;
        Ok(if self.frames_seen <= WARMUP_FRAMES { 0.0 } else { score })
    }
}

impl Scorer for TractScorer {
    /// A frame the models cannot score (a short one, or a tract error) scores 0.
    fn score(&mut self, frame: &[i16]) -> f32 {
        if frame.len() != FRAME_SAMPLES {
            return 0.0;
        }
        self.try_score(frame).unwrap_or(0.0)
    }

    fn reset(&mut self) {
        self.context.clear();
        self.mel_rows = vec![1.0; MEL_WINDOW_ROWS * MEL_BINS];
        self.features = INITIAL_FEATURES
            .as_chunks::<4>()
            .0
            .iter()
            .map(|bytes| f32::from_le_bytes(*bytes))
            .collect();
        self.frames_seen = 0;
    }
}

/// Fixed input shapes, because tract optimizes for them: the models take any length, the plans do not.
fn load_plan(path: &Path, shape: &[usize]) -> Result<Plan, String> {
    let describe = |error: tract_onnx::prelude::TractError| format!("{}: {error}", path.display());
    onnx()
        .model_for_path(path)
        .and_then(|model| model.with_input_fact(0, f32::fact(shape).into()))
        .and_then(|model| model.into_optimized())
        .and_then(|model| model.into_runnable())
        .map_err(describe)
}

fn run(plan: &Plan, shape: &[usize], data: Vec<f32>) -> TractResult<Vec<f32>> {
    let input = Tensor::from_shape(shape, &data)?;
    let output = plan.run(tvec!(input.into()))?;
    Ok(output[0].to_plain_array_view::<f32>()?.iter().copied().collect())
}

fn keep_last(values: &mut Vec<f32>, count: usize) {
    if values.len() > count {
        values.drain(..values.len() - count);
    }
}
