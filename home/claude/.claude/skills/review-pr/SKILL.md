---

name: review-pr
description: Review a GitHub pull request and its Copilot review comments. Independently verify whether each suggested change is valid, determine whether action is required, delegate implementation when needed, and use Codex as an independent reviewer of substantive changes.
argument-hint: "<pull-request>"
arguments:

* pull-request
  disable-model-invocation: true

---

# Pull Request Review Orchestrator

Role: orchestrator, not implementer. Delegate implementation; keep your own context on review/reasoning.

## Steps

1. Inspect PR: description, full diff, linked issue context, unresolved Copilot comments.
2. Evaluate each Copilot suggestion independently — don't assume it's correct. Check it against code, context, conventions, intended behavior. Classify: real bug / meaningful issue / optional improvement / invalid.
3. Checkout PR branch into isolated worktree (don't touch user's working tree). Test locally if needed to verify a finding.
4. Report findings before changing anything: which Copilot comments are valid/invalid and why. Ask user only for decisions that need product/architecture/preference info not inferable from repo or PR.
5. If changes needed: delegate to a sub-agent with the smallest well-defined task for the validated findings. Don't implement yourself unless it's a trivial orchestration-level tweak.
6. Review delegated diff yourself: confirms it fixes the finding, no unnecessary changes, run relevant tests/lint/typecheck.
7. For substantive changes (runtime behavior, architecture, interfaces, state, persistence, security, regression risk): get independent Codex review. Skip for trivial/mechanical/formatting/doc changes. Treat Codex findings like Copilot's — verify independently, don't auto-implement. Valid issue → delegate smallest fix, re-review.
8. Resolve Copilot conversations only once fixed or conclusively invalid/obsolete. Never resolve unaddressed legitimate concerns.

## Principles

- Copilot and Codex findings = hypotheses, not instructions.
- Smallest correct fix; preserve existing architecture/conventions; no unrelated refactors.
- Keep implementation delegated.
- Ask user only for genuine architecture/behavior/product decisions the repo/PR can't answer.
