# Reviewer registry

`reviewers.sh list [repo_dir]` prints the merged registry as one JSON array. `repo_dir` (default: the current directory) selects the repo layer.

## Layers, lowest to highest

1. Built-in: `reviewers.json` beside the script.
2. User: `~/.config/code-reviewers/reviewers.json` (`$XDG_CONFIG_HOME`).
3. Settings: `$XDG_STATE_HOME/quickshell/developer.json` (written only by Settings > Developer).
4. Repo: `<repo root>/.claude/reviewers.json`.

Layers 1, 2 and 4 are `{"reviewers": [entry, ...]}`. Settings is a map that may set only `local` (a scope, or `{"scope": ...}`; other `local.*` keys are ignored) and `gate`, and only on entries that already exist:

```json
{"reviewers": {"codex": {"local": "all", "gate": "auto"}}}
```

Entries merge by `name`: objects field by field, arrays replaced. `"enabled": false` drops an entry (a higher layer can set it back to `true`). A string `local` is shorthand for `local.scope`.

## Entry fields

- `name` (required, unique), `label`.
- `local`: `command` (`<cmd> <base> <outdir>`), `binary` (probed for "installed"), `default` and `default_when_on` (scopes), `scope` (the user's choice).
- `github` (absent or null = never gates): `app_slug`, `logins`, `check_names`, `signal` (`summary_comment` or `check_run`), `running`, `done`, `unavailable`, `unavailable_conclusions`, `request`, `start_s`, `wait_s`.
- `gate`: `auto`, `always` or `never`.

Scopes are `off`, `public`, `all`. Output always has `local.scope` (from `local.scope`, else `local.default`, else `off`, so an entry without local config gets `off`) and `gate` (default `auto`); `enabled` is removed.

## Errors and exit codes

- A layer that is not valid JSON or has the wrong shape is skipped with a warning on stderr; the other layers still resolve. An invalid scope or default becomes `off`; an invalid `gate` or `enabled` is ignored.
- Any problem in the built-in file is fatal.
- Exit 0 on success, 1 on a missing or invalid built-in file, 64 on bad usage.

## Local runner

`run-local-reviews.sh <base> <outdir>` runs every reviewer whose resolved `local.scope` is not `off`, in parallel, from the current (clean) worktree, and prints one line per reviewer. It always exits 0 (results are advisory); 1 if the registry does not resolve or the results cannot be copied into the outdir.

Each `local.command` (relative paths resolve beside the script) is called as `<cmd> <base> <outdir>` with `REVIEW_SCOPE` (the resolved scope) and `REVIEW_MODEL` (`local.model`, optional) in the environment, and writes `<outdir>/<name>-review.md`; every other file it writes must be named `<name>-*` or `<name>.*`, because the runner deletes those before each run.  Exit codes: 0 path printed; 2 unavailable (reason printed); 3 uncommitted changes; 4 skipped by scope (reason printed, kept in `<outdir>/<name>-skipped.txt`). Scripts source `review-lib.sh` for the scope check: `public` needs `gh repo view --json visibility` to say public (looked up live on every run, never cached, so a repo that went private stops being reviewed at once); a failed lookup counts as private. Called directly without `REVIEW_SCOPE`, a script looks its scope up in the registry.

The `<outdir>` a reviewer receives from the runner is a staging directory outside the worktree; the runner copies it into the real outdir after every reviewer has finished, and rewrites the printed paths. A reviewer's own clean-tree check therefore never sees a sibling's output, even when the outdir is inside the repo and not ignored.
