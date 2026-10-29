# Use cases

Patterns for text types that the main rules do not cover alone. Commit messages, PR bodies and issues have their own skills. Those skills set the structure, and `SKILL.md` sets the sentences. Adapted from SimpleEnglish (see `../LICENSE`).

## Chat replies

The reader skims. Make skimming safe:

- The first sentence gives the result, the answer or what you need from the reader.
- Put decisions, risks, blockers and assumptions next, each on its own line. A short list is better than a paragraph for these.
- Leave supporting analysis out unless the reader asks for it.
- Gloss each term that you coined during the work. The reader did not see your tool calls.

## Error messages and CLI output

The reader is in the middle of a failure. State what happened (simple past), the cause if you know it, and the command or condition that fixes it.

> Before: Oops! Something went wrong while attempting to establish a connection. Please ensure your credentials are properly configured and try again.
>
> After: Connection to the database failed. The password for user `app` was not correct. Set `DB_PASSWORD` and connect again.

## Runbooks and procedures

- Write each step in the imperative, one instruction per step, with the condition first.
- Put a warning before its step: the command first, the risk second.
- Keep each sentence to 20 words.

## Incident reports

Use the simple past only. A timeline in the present perfect ("we have identified") hides when things happened. State what is known and write "unknown" for the rest.

> Before: We have identified an issue that may have impacted some users' ability to access the service.
>
> After: Between 14:02 and 14:31 UTC, 12% of requests failed. A deploy at 14:00 removed the cache warmup step.

## Changelogs and release notes

Write one entry for each change, in one sentence where possible. Write a breaking change as a warning, command first: "Update your calls to `v2/users`. The `name` field is now `first_name` and `last_name`."

## Instructions for agents (prompts, AGENTS.md, skills)

A prompt is a procedure for a reader that cannot ask questions.

- Write one instruction per sentence, so that each rule is easy to quote and hard to half-follow.
- Use one word for one meaning. Otherwise a model treats "check", "verify" and "validate" as three operations.
- Put the condition first: "If the build fails, stop." A model drops a trailing condition more often.
- Do not write "should". A model reads it as optional. Write "must", or delete the rule.

## UI copy

Buttons and labels are names and are exempt. Body copy follows the rules: "No projects yet. Create a project to start."

## Where these rules do not fit

Marketing pages, launch posts, blog posts and personal writing need a voice and persuasion, which these rules remove. Say so, and offer the rules for the docs that those texts link to.
