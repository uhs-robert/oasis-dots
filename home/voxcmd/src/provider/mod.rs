//! The built-in candidate providers: a `provider = "<name>"` line in an integration's toml sends the candidates lookup
//! here instead of to a shell hook. Each provider is one `Provider` variant and one arm of `BuiltinHooks::candidates`.
mod monitors;
mod screen_text;

use crate::click::capture::Tools;
use crate::click::driver::WindowSel;
use crate::click::explain::ExplainSink;
use crate::config::schema::{Candidates, Integration, Provider};
use crate::hooks::{HookQuery, HookRun, Hooks};

pub struct BuiltinHooks {
    /// What `screen_text` reads the window with.
    tools: Tools,
    /// `explain --window`: where each answer leaves its trace, and which window it reads. A click proper has neither.
    explain: Option<ExplainSink>,
    window: WindowSel,
}

impl Default for BuiltinHooks {
    fn default() -> Self {
        Self {
            tools: Tools::default(),
            explain: None,
            window: WindowSel::Focused,
        }
    }
}

impl BuiltinHooks {
    /// Hooks for `explain --window`: they read `window`, write no click-target, and record a trace of every answer.
    pub fn tracing(window: WindowSel, sink: ExplainSink) -> Self {
        Self {
            explain: Some(sink),
            window,
            ..Self::default()
        }
    }
}

impl Hooks for BuiltinHooks {
    fn candidates(&self, integration: &Integration, query: &HookQuery) -> HookRun {
        match integration.candidates_for(query.action) {
            Some(Candidates::Builtin(Provider::ScreenText)) => self.screen_text(integration, query),
            Some(Candidates::Builtin(Provider::Monitors)) => self.monitors(integration, query),
            _ => HookRun::unhooked(integration, query.action, ""),
        }
    }

    fn surface_open(&self, _integration: &Integration) -> bool {
        false
    }
}
