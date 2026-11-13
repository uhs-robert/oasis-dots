"""Where a doc sits in the repo's rank order: the midpoint between two neighbours and the renumber when none is left.

The board's drag (server) and `plans new --after/--before` (cli) share this. Each caller supplies its own refusal
check and exception, because the board answers HTTP and the CLI prints a message.
"""

from . import parse, store

RANK_STEP = 10


def rank_between(above, below):
    """A whole number strictly between the two ranks (None means no card on that side), or None when there is none.
    A rank stays at 0 or above, because the front matter subset has no negative numbers."""
    if above is None:
        return below - RANK_STEP if below >= RANK_STEP else (below // 2 if below > 0 else None)
    if below is None:
        return above + RANK_STEP
    return (above + below) // 2 if below - above >= 2 else None


def renumbered_ranks(order):
    """path -> RANK_STEP, 2 * RANK_STEP and so on, in the order of `order`."""
    return {doc.path: RANK_STEP * (index + 1) for index, doc in enumerate(order)}


def renumber_others(order, moved, new_ranks, check_under_lock, refused):
    """Write `new_ranks` to every doc in `order` except `moved`. Each doc is its own store.update: a doc that an agent
    re-ranked meanwhile keeps the agent's rank and lands in `skipped`, as does a doc that `check_under_lock` refuses
    by raising one of `refused`. A doc whose write failed partway lands in `uncertain`: the new rank may have landed.
    Returns (count written, skipped, uncertain), each entry {path, id, error}."""
    written, skipped, uncertain = 0, [], []
    for doc in order:
        if doc is moved or doc.keys["rank"] == new_ranks[doc.path]:
            continue
        try:
            store.update(doc, {"rank": new_ranks[doc.path]}, check_under_lock=check_under_lock)
            written += 1
        except (store.Conflict, store.Vanished, parse.ParseError, UnicodeDecodeError, *refused) as error:
            skipped.append({"path": doc.path, "id": doc.id, "error": str(error)})
        except OSError as error:
            uncertain.append({"path": doc.path, "id": doc.id, "error": str(error)})
    return written, skipped, uncertain
