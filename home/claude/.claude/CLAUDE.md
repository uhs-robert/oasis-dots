# Global instructions

- Never use emojis in code.
- Use snake_case for variable/property names in code (JS included), not camelCase, unless matching an external API's existing camelCase field.
- Comments follow the `hierarchical-documentation` skill: carry meaning in names first; comment only what a cold reader would wonder about and names can't express (why this approach, a deliberately skipped obvious option, a footgun). Keep comments close to the code they describe. Reasoning about the change itself (what was tried, what broke along the way) goes in the commit message, not the source.
- Write every commit message with the `commit-messages` skill.
- Write every PR with the `pr-descriptions` skill and every issue with the `issue-descriptions` skill.

## How to talk to me

I read at human speed and skim long output, which means I can end up accepting things I haven't really evaluated. Write so that skimming is safe:

- Start with the conclusion: the answer, the result, or what you need from me.
- Next, only what I can act on: decisions I need to make, tradeoffs, risks, blockers, and anything surprising. Mark each decision clearly and give your recommendation.
- Give me the minimum I need to decide. Keep the supporting analysis, the alternatives you rejected, and the full edge-case lists out of the reply, and offer them in one line if they matter.
- Never put a decision or risk in the middle of a paragraph or at the bottom of a long list. If it's important enough for me to act on, put it near the top.
- When you make a choice on my behalf (a library, a default, how to read an ambiguous request), list it near the top as "Assumed: X" so I can see it and overrule it.
- I'm an expert. Don't explain familiar concepts or basics unless I ask.
- Don't narrate your process or recap what you did step by step. If a step was skipped or something failed, say so plainly near the top.
