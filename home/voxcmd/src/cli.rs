//! the clap types for every subcommand and flag; nothing else
use clap::{Args, Parser, Subcommand};

/// Phrases are the positional words, joined with one space by the handler; `--` ends the flags so a phrase can start
/// with `-`.
#[derive(Parser, Debug)]
#[command(
    name = "voxcmd",
    about = "Voice command router",
    disable_help_subcommand = true,
    subcommand_required = true,
    arg_required_else_help = true
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Route a phrase ("and then" sequences included) and act on it
    Run(PhraseArgs),
    /// Print the routing trace of a phrase without acting on it
    Explain(ExplainArgs),
    /// Answer the open picker or confirm card with a spoken phrase
    Reply(ReplyArgs),
    /// Start a listen turn
    Listen {
        /// Start the recording and return; the turn ends elsewhere
        #[arg(long)]
        start_only: bool,
    },
    /// End the session and cancel anything open or recording
    Stop,
    /// Voice sessions
    #[command(subcommand)]
    Session(SessionCommand),
    /// Open a picker, confirm card or hints overlay and print the answer
    #[command(subcommand)]
    Ask(AskCommand),
    /// The wake-word listener
    #[command(subcommand)]
    Wake(WakeCommand),
    /// Inspect the integrations
    #[command(subcommand)]
    Integrations(IntegrationsCommand),
    /// Open the example-phrase picker
    Help,
    /// Read the logs of phrases and notifications
    #[command(subcommand)]
    Log(LogCommand),
    /// Timer units
    #[command(subcommand)]
    Timer(TimerCommand),
    /// Helpers for integration hooks
    #[command(subcommand, hide = true)]
    Util(UtilCommand),
    /// Entry points the listeners and watchers call; not a stable interface
    #[command(subcommand, hide = true)]
    Internal(InternalCommand),
}

#[derive(Args, Debug)]
pub struct PhraseArgs {
    /// The phrase, as spoken
    #[arg(required = true, num_args = 1..)]
    pub phrase: Vec<String>,
}

#[derive(Args, Debug)]
pub struct ExplainArgs {
    /// Print one JSON document instead of text
    #[arg(long)]
    pub json: bool,
    /// Add the click trace of this window (a Hyprland stable id, or `focused`) for a `click ...` phrase
    #[arg(long, value_name = "STABLE_ID")]
    pub window: Option<String>,
    /// Explain a reply against the open picker or confirm card
    #[arg(long)]
    pub reply: bool,
    /// The phrase, as spoken
    #[arg(required = true, num_args = 1..)]
    pub phrase: Vec<String>,
}

#[derive(Args, Debug)]
pub struct ReplyArgs {
    /// Print what the reply would pick (`picker:`, `confirm:`, `result:`) without answering
    #[arg(long)]
    pub dry_run: bool,
    /// The spoken answer
    #[arg(required = true, num_args = 1..)]
    pub phrase: Vec<String>,
}

#[derive(Subcommand, Debug)]
pub enum SessionCommand {
    /// Open a rapid-fire session
    Rapid,
    /// End the open session
    End,
}

#[derive(Args, Debug)]
pub struct AskArgs {
    /// Listen for the answer by voice too
    #[arg(long)]
    pub listen: bool,
}

#[derive(Subcommand, Debug)]
pub enum AskCommand {
    /// Pick one of several choices; prints the picked id
    Pick {
        #[command(flatten)]
        ask: AskArgs,
        label: String,
        /// JSON array of choices
        choices_json: String,
        /// JSON object of expansions
        expansions_json: Option<String>,
    },
    /// Ask a yes/no question; exit 0 means yes
    Confirm {
        #[command(flatten)]
        ask: AskArgs,
        /// The verb the card names
        #[arg(long)]
        verb: Option<String>,
        question: String,
    },
    /// Number boxes on screen and pick one; prints the picked id
    Hints {
        #[command(flatten)]
        ask: AskArgs,
        label: String,
        /// JSON array of choices, each with a `box`
        choices_json: String,
    },
}

#[derive(Subcommand, Debug)]
pub enum WakeCommand {
    /// Arm the wake-word listener
    On,
    /// Disarm the wake-word listener
    Off,
    /// Switch the listener on or off
    Toggle,
    /// Print `on` or `off`; exit 1 when off
    Status,
    /// Run the listener (the service's entry)
    Listen {
        /// Download the wake models and exit
        #[arg(long)]
        fetch_models: bool,
        /// Check the models and the microphone, then exit
        #[arg(long)]
        check: bool,
    },
}

#[derive(Args, Debug)]
pub struct JsonFlag {
    /// Print one JSON document instead of text
    #[arg(long)]
    pub json: bool,
}

#[derive(Subcommand, Debug)]
pub enum IntegrationsCommand {
    /// List the integrations and their verbs
    List(JsonFlag),
    /// Validate every integration file; exit 1 when there are problems
    Check {
        #[command(flatten)]
        json: JsonFlag,
        /// Files to check (default: all)
        files: Vec<String>,
    },
    /// List every integration's example phrases
    Examples {
        #[command(flatten)]
        json: JsonFlag,
        /// Route each placeholder-free example and report where it lands
        #[arg(long)]
        route: bool,
    },
    /// Print the JSON Schema of an integration file
    Schema,
}

#[derive(Subcommand, Debug)]
pub enum LogCommand {
    /// The phrases that matched nothing, newest last
    Misses {
        #[command(flatten)]
        json: JsonFlag,
        /// How many to print
        #[arg(default_value_t = 20)]
        count: u32,
    },
    /// The bar's recent voxcmd notifications
    Errors {
        #[command(flatten)]
        json: JsonFlag,
        /// How many to print
        #[arg(default_value_t = 10)]
        count: u32,
    },
}

#[derive(Subcommand, Debug)]
pub enum TimerCommand {
    /// Ring a timer: run by the timer units
    Ring {
        summary: String,
        #[arg(default_value = "")]
        body: String,
    },
}

#[derive(Subcommand, Debug)]
pub enum UtilCommand {
    /// Show a toast with voxcmd's app name
    Notify { level: String, title: String, body: String },
    /// Print the spoken forms of an intent, one per line
    Intents { name: String },
    /// Parse or format spoken times, durations and days
    #[command(subcommand)]
    Speech(SpeechCommand),
    /// Filter `id<TAB>label<TAB>match_text` lines on stdin by how well they match a target
    WordMatch {
        /// Words to leave out of the comparison
        #[arg(long, value_name = "WORDS")]
        ignore: Option<String>,
        /// Print only strong matches (the same words), dropping weak near misses
        #[arg(long)]
        strong: bool,
        target: String,
    },
    /// Print the pending pick's state while its asker waits; exit 1 when none does
    PendingPick,
    /// Print a voice setting from the environment or voice.env; exit 1 when unset
    VoiceEnv { key: String },
}

#[derive(Subcommand, Debug)]
pub enum SpeechCommand {
    /// "at 3:47pm" for today, "tomorrow 9:00am" otherwise, from epoch seconds
    FormatAt {
        #[arg(allow_hyphen_values = true)]
        epoch: String,
    },
    /// "1 hour 30 minutes", from seconds
    FormatLength {
        #[arg(allow_hyphen_values = true)]
        seconds: String,
    },
    /// "3:47pm", "tomorrow 9:00am", "Thu 9:00am" or "Oct 20 9:00am", from epoch seconds
    FormatDue {
        #[arg(allow_hyphen_values = true)]
        epoch: String,
    },
    /// The epoch seconds a clock time names ("3 pm", "friday at 9", "noon")
    ParseTime {
        /// A time already past today stays today, for converting a time rather than scheduling one
        #[arg(long)]
        today: bool,
        #[arg(required = true, num_args = 1..)]
        words: Vec<String>,
    },
    /// The seconds a duration names ("5 minutes", "an hour and a half")
    ParseDuration {
        #[arg(required = true, num_args = 1..)]
        words: Vec<String>,
    },
    /// "<seconds> <label>" from the longest leading duration of a phrase ("5 minutes for the pasta"); exit 1 when none leads
    SplitDuration {
        #[arg(required = true, num_args = 1..)]
        words: Vec<String>,
    },
    /// The date (YYYY-MM-DD) a day word names ("today", "tomorrow", "friday", "next friday")
    ParseDay {
        #[arg(required = true, num_args = 1..)]
        words: Vec<String>,
    },
}

/// The hidden entry points. The old underscore spellings stay as aliases until the Python listeners move (phase 4);
/// main routes a top-level `_name` here.
#[derive(Subcommand, Debug)]
pub enum InternalCommand {
    #[command(alias = "_watch")]
    Watch(InternalArgs),
    #[command(alias = "_settle")]
    Settle(InternalArgs),
    #[command(alias = "_cancel_owned_recording")]
    CancelOwnedRecording(InternalArgs),
    #[command(alias = "_wake-confirm")]
    WakeConfirm(InternalArgs),
    #[command(alias = "_chain-stop")]
    ChainStop(InternalArgs),
    /// The session as a bash integration's hooks reach it (begin, leave, end, end-all, state)
    Session(InternalArgs),
    /// The click matcher on click-ocr's output (stdin); the target is in CLICK_TARGET. Deleted with the bash matcher (3.2)
    #[command(hide = true)]
    ClickMatch(ClickMatchArgs),
    /// Captures a window and prints its word boxes for click-match: `[--window <stableId>] [--explain]`, read by hand so
    /// the usage line is click-ocr's. Deleted with the bash script (3.2)
    #[command(hide = true)]
    ClickOcr(InternalArgs),
    /// Clicks the candidate id (`x,y,button,left,top,width,height`, or `error:<why>` or `covered:`) as an action does:
    /// prints the reason and exits 1 when it fails. `--target` is the spoken text a covered-text toast names. Deleted
    /// with the bash click.sh (3.2)
    #[command(hide = true)]
    ClickAt(ClickAtArgs),
}

#[derive(Args, Debug)]
pub struct ClickAtArgs {
    /// The spoken target
    #[arg(long, default_value = "", allow_hyphen_values = true)]
    pub target: String,
    /// The candidate id; a negative coordinate (a monitor left of the origin) starts with a dash
    #[arg(allow_hyphen_values = true)]
    pub id: String,
}

#[derive(Args, Debug)]
pub struct ClickMatchArgs {
    /// Search each run for sub-spans instead of matching whole runs (the awk's CLICK_SPANS)
    #[arg(long)]
    pub spans: bool,
    /// Write the trace to stderr
    #[arg(long)]
    pub explain: bool,
}

#[derive(Args, Debug)]
pub struct InternalArgs {
    /// Arguments as the bash entry point took them
    #[arg(num_args = 0.., allow_hyphen_values = true, trailing_var_arg = true)]
    pub args: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::CommandFactory;

    #[test]
    fn the_tree_is_consistent() {
        Cli::command().debug_assert();
    }
}
