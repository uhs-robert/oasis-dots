# Fleet roster (<date>)

<session_count> orchestrators run at once in full auto. <coordinator_line> Each orchestrator coordinates its own work with its peers through `SendMessage`. Find a peer's address with `ListAgents`. A session's name is the name in the first column below.

## Bundles

Each session runs with a context budget of <budget> tokens and takes work sized to about <work_tokens>.

| Session | Pieces, in build order |
|---|---|
| <session> | <pieces_in_order> |

## Cross-bundle order

One bullet per dependency between bundles. Name who waits, for what merge, and who messages whom when it lands.

- <waiting_session> waits for <other_session> to merge <piece>. <other_session> messages <waiting_session> when it merges. Until then <waiting_session> does the design and the parts that do not depend on it.

## Shared files

- <file>: <rule, such as a byte budget, a regenerate step after a rebase, or who merges first>.

## Outside sessions

Sessions that are not part of this fleet but work in the same repo. Their merges and rebases reach the fleet, so each fleet session expects them.

- <outside_session>: <what it works on and which files it touches>.

## Owner rules for this run

- Merge through the repo's merge step, <merge_step>, only. Run it once its check passes and the reviewer agent approves with no revisions.
- <hand_check_rule>
- <release_rule>
- <excluded_pieces_rule>

## Session names

Each orchestrator appends its `ListAgents` name here when it starts:
