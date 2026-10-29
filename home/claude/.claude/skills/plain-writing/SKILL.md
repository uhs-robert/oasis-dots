---
name: plain-writing
description: >-
  Sentence and word rules for all English prose an agent writes: chat replies, commit messages, PR and issue bodies, READMEs, docs, code comments and agent instructions. Lead with the point, short sentences, active voice, no hedging modals, no contractions, no filler, plain words for concepts and a short gloss for project terms. Use whenever you write or rewrite prose, and when another skill (commit-messages, pr-descriptions, issue-descriptions, hierarchical-documentation) points here.
---

# Plain Writing

Write so that a smart reader from outside the project understands the text on one read. This skill governs sentences and words. The skill for each artifact (a commit, a PR, an issue, a comment) governs its structure and length. If the two disagree, the artifact skill wins on structure and this skill wins on sentences.

The rules are adapted from [SimpleEnglish](https://github.com/AminBlg/SimpleEnglish) (commit `a6fcb4f`, MIT, see `LICENSE`), which adapts ASD-STE100 Simplified Technical English. This copy leaves out the STE dictionary, the audit mode and the prose-only reply rule.

## Lead with the point

1. The first sentence gives the answer, the result or the decision. Do not restate the question or the task.
2. Put a decision, a risk or a required action near the top. Never put it inside a paragraph or at the end of a list.

## Sentences

3. Classify each passage:
   - An instruction tells the reader what to do. Use the imperative mood, one instruction per sentence, and 20 words at most.
   - A description explains. Use 25 words at most, one new fact per sentence, one topic per paragraph, and six sentences per paragraph at most.
   - Code, an identifier, a number with its unit and quoted text each count as one word.
4. Put the condition before the command, with a comma: "If the build fails, read the log."
5. Use simple tenses and the active voice, and name the actor. "The config has been updated" becomes "I updated the config" or "The script updates the config." Do not put an "-ing" verb after a comma (", making it easy to"). Start a new sentence instead.
6. Use can, will and must. Do not use should, would, may, might or could. Replace each one by what it means:

   | You wrote | Write instead |
   |---|---|
   | should (a requirement) | must |
   | should (a recommendation) | Delete it, or state the reason: "X is better because Y." |
   | should (as "if": "should a failure occur") | if |
   | may, might, could (a possibility) | can, or state the condition: "If X, Y happens." |
   | may (a permission) | can |
   | would (a hypothetical) | can, or restructure: "If X happens, Y happens." |
   | could not (past ability) | did not, was not able to |

7. Use complete grammar. Do not use contractions ("don't", "it's", "we'll"). Keep articles and keep "that". Short does not mean telegraphic: "Make sure that the file exists before you run the command", not "Ensure file exists before running." A possessive ("the user's file") is not a contraction.
8. Do not use semicolons, em-dashes, or a spaced or double hyphen between clauses. Write two sentences, or name the relation: because, but, so, for example. A range (`5-10`) and a flag (`--force`) are not dashes.
9. Use a connecting word between related sentences: then, as a result, but.
10. Use a one-word verb when one exists: "install", not "set up". "decrease", not "go down".

## Words

11. Use one word for one meaning through the whole text. Pick one name for each thing and keep it. Do not write "config" in one paragraph and "settings" in the next for the same file.
12. Keep noun chains to three words. Break a longer chain with a preposition: "the timeout value for the connection pool", not "the connection pool timeout configuration value".
13. Do not use a noun as a verb ("webhook the event") or a verb as a noun ("do a deploy").
14. State the fact, not its importance. Delete words that carry no fact. `references/word-swaps.md` lists the common ones. Also delete:
    - "not just X, it is Y" constructions and decorative groups of three.
    - Summaries that repeat the text ("In conclusion", "In short").
    - Openers ("Great question", "Certainly") and closers ("Let me know if", "I hope this helps").
    - Vague sources ("studies show"). Name the source or drop the claim.
15. Use American spelling.
16. Write "for example" and "that is". Name the items instead of "etc."

## Jargon and names

17. Describe a concept in plain words. Put each exact identifier in backticks: commands, flags, file paths, functions, configuration keys and quoted errors.
18. Give a project term or a term you coined during the work a short gloss at its first use: "the replica (a read-only copy of the database that reports query)". Do not gloss standard terms and product names (HTTP, git, Postgres). Do not invent a name for a thing when a plain description fits in a few words.
19. Do not list an inventory of keys, files, apps or test fixtures in prose. Summarize the group ("the 14 endpoints it used to serve"), and name only the items that the reader must act on.
20. Name the host, the flag or the earlier step that a command depends on. "Restart the service" becomes "Restart the `sync` service on the host that runs the job."

## Formatting

21. Use formatting only where it carries structure. Do not use bold for emphasis or bold labels on list items (`- **Cleanup:** ...`). Do not use emoji. Do not put a heading over a section shorter than three paragraphs.
22. Use a vertical list for three or more parallel items, options or steps: a colon on the lead-in line and one item per line.
23. Put a warning before its step. Give the command or condition first, then the risk: "Do not run this against production. It deletes the rows that do not match."

## Never change

Do not change code, identifiers, commands, quoted errors, product names or facts. Do not shorten quoted error text, security warnings or the confirmation before a destructive action. If the source gives no number or cause, keep the general statement. Do not invent a number or a cause.

## Before and after

Documentation:

> Before: Leveraging sqlpipe's robust architecture, users can seamlessly synchronize their Postgres tables to S3 with minimal configuration overhead. Before getting started, you should ensure that your AWS credentials have been properly configured — this is crucial for avoiding frustrating permission issues down the line.
>
> After: sqlpipe copies your Postgres tables to S3. It needs one configuration file. Before you start, make sure that your AWS credentials are correct. If they are not, S3 rejects the upload with a permission error.

A commit body:

> Before: It shows up in the shared `ReportView` (the admin dashboard's Usage tab and the CSV fallback), in every per-tenant layout in that tenant's own wording, and as a short suffix on the monthly rows of the email digest, though the billing badge itself is unchanged.
>
> After: The forecast appears in every report view and in the email digest. Each tenant layout uses its own wording. The billing badge does not change.

A chat reply:

> Before: Great question! The failure stems from control-plane leader election during pod churn — nothing to worry about, it should resolve itself.
>
> After: You do not have to do anything. The pods restarted, and the queue lost its leader (the node that hands out work) for a short time. It recovered without help.

## Self-check

Do these steps before you deliver the text:

1. Read the first sentence. If it does not give the answer, the result or the decision, move that sentence up.
2. Count the words in the three longest sentences. Split each one over 20 words (an instruction) or 25 words (a description).
3. Search for contractions (`n't`, `'re`, `'ll`, `'ve`, `'d`, and `'s` where it means "is" or "has"). Expand each one.
4. Search for `should`, `would`, `may`, `might`, `could`, `;`, `—`, ` -- `, `has been`, `have been`, and an "-ing" verb after a comma. Fix each hit.
5. Search for the words in `references/word-swaps.md`. Replace or delete each hit.
6. Find each project term and each term you coined. Gloss it at its first use, or put it in backticks if it is an identifier.
7. Find each run of more than five names in prose. Summarize the group.

## References

- `references/word-swaps.md`: overused words and their plain replacements.
- `references/use-cases.md`: patterns for chat replies, error messages, runbooks, incident reports, release notes and agent instructions.
