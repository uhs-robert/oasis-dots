"""`plans serve`: one local web board over the plan docs of every repo under the roots.

The board reads each repo through query.read_repo, so it sees what `plans ls --all` sees. A watcher thread polls the doc
mtimes and pushes a new board version to the page by server-sent events. Every write goes through store.update, with
the values the page showed as the basis, so an edit made after the page last loaded refuses the write.
"""

import http.server
import json
import os
import shlex
import signal
import subprocess
import sys
import threading
import time
import urllib.parse

from typing import NamedTuple

from . import liveness, parse, query, retire, roots, store, validate

HOST = "127.0.0.1"
DEFAULT_PORT = 8765
POLL_SECONDS = 1
RESCAN_SECONDS = 30
KEEPALIVE_SECONDS = 15
PAGE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "board.html")
GITHUB_REMOTE_PREFIXES = ("git@github.com:", "https://github.com/", "ssh://git@github.com/")
# The page sends this header with every write. A page on another site cannot add a custom header to a request here
# without a CORS preflight, and this server answers none, so a forged cross-site write never gets through.
WRITE_HEADER = "X-Plans-Board"
MAX_BODY_BYTES = 64 * 1024
# The board edits only these through /api/update. Rank changes go through /api/move, and the rest stays read-only.
EDITABLE_KEYS = ("status", "owner_session")
RANK_STEP = 10
# Hyprland writes this launcher for the terminal it opens. $TERMINAL is the fallback outside that desktop.
HYPR_TERMINAL = os.path.join("hypr", "bin", "term")
FALLBACK_EDITOR = "nvim"
# `tailscale serve` sets this to the login of the tailnet user behind each request, after it drops any value the
# client sent. It leaves the header out for a tagged node, a Funnel request and a request from outside the tailnet.
LOGIN_HEADER = "Tailscale-User-Login"
# The phone may change status, owner, rank and the body. Opening the editor and cancelling stay on the laptop.
REMOTE_ACTIONS = ("/api/update", "/api/move", "/api/toggle", "/api/section")
# A section edit from the board holds at most this much text. A plan doc section is far smaller.
MAX_SECTION_BYTES = 16 * 1024


class Remote(NamedTuple):
    """The phone's way in: the board's MagicDNS name and the one tailnet login that may use it."""
    host: str
    login: str


def remote_config_file():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "plans", "remote.json")


def load_remote(path=None):
    """The Remote from remote.json, or None, which keeps the board local only. A broken file also keeps it local,
    and says why on stderr, so a typo never opens the board wider than intended."""
    path = path or remote_config_file()
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as error:
        print(f"plans serve: {path}: {error}; remote access stays off", file=sys.stderr)
        return None
    values = [data.get(key) if isinstance(data, dict) else None for key in ("host", "login")]
    if not all(isinstance(value, str) and value.strip() for value in values):
        print(f"plans serve: {path} needs a \"host\" and a \"login\" string; remote access stays off", file=sys.stderr)
        return None
    host, login = (value.strip() for value in values)
    # `tailscale status --json` gives the name with the DNS root dot, which no Host header carries.
    return Remote(host.rstrip(".").lower(), login)


class Refused(Exception):
    """A write the server turns down before it reaches store.update."""

    def __init__(self, code, message, **extra):
        super().__init__(message)
        self.code = code
        self.data = {"error": message, **extra}


class RepoView(NamedTuple):
    root: str
    repo: object
    # Set when the repo could not be read at all, for example a doc without read permission.
    error: str
    web_url: str


class Board:
    """The current read of every repo, and a version number that grows with each change the watcher sees."""

    def __init__(self, roots_file=None, poll_seconds=POLL_SECONDS, rescan_seconds=RESCAN_SECONDS):
        self.roots_file = roots_file
        self.poll_seconds = poll_seconds
        self.rescan_seconds = rescan_seconds
        self.poll_lock = threading.Lock()
        self.changed = threading.Condition()
        self.stopping = threading.Event()
        # A restarted server must count as newer to a page still open on the old one, which ignores older versions.
        # Microseconds keep the number exact in JavaScript, which holds integers exactly only up to 2**53.
        self.version = time.time_ns() // 1000
        self.views = {}
        self.signatures = {}
        self.repo_roots = []
        self.last_rescan = None
        self.web_urls = {}

    def poll(self, rescan=False):
        """Read again each repo whose docs changed on disk. Bumps the version and wakes the event streams on a change."""
        with self.poll_lock:
            now = time.monotonic()
            if rescan or self.last_rescan is None or now - self.last_rescan >= self.rescan_seconds:
                self.repo_roots = roots.all_repos(self.roots_file)
                self.last_rescan = now
            views, signatures, changed = {}, {}, list(self.views) != self.repo_roots
            for root in self.repo_roots:
                # The signature comes before the read: a write in between shows as a change at the next poll.
                signatures[root] = docs_signature(root)
                # An owner can die with no file change, so a cached view with a dead owner is read again.
                cached = self.views.get(root)
                files_unchanged = cached is not None and self.signatures.get(root) == signatures[root]
                if files_unchanged and not holds_dead_owner(cached):
                    views[root] = cached
                    continue
                views[root] = self.read_view(root)
                # A release that keeps failing, on an unwritable doc, must not bump the version on every poll.
                changed = changed or not files_unchanged or doc_texts(views[root]) != doc_texts(cached)
            # Both are replaced only once every repo read, so a failed poll leaves no view behind its signature.
            self.signatures = signatures
            if changed:
                with self.changed:
                    self.views = views
                    self.version += 1
                    self.changed.notify_all()

    def read_view(self, root):
        if root not in self.web_urls:
            self.web_urls[root] = github_web_url(root)
        error = None
        # One retry covers a doc deleted or renamed between the glob and the read. A doc that still fails stays an error.
        for _ in range(2):
            try:
                repo = query.read_repo(root)
                # The freed card shows owner none, which says enough. The CLI names each release on stderr.
                return RepoView(root, repo._replace(docs=liveness.release_dead_owners(repo.docs)[0]), None, self.web_urls[root])
            except OSError as failure:
                error = f"{failure.filename or root}: {failure.strerror or failure}"
            except UnicodeDecodeError as failure:
                error = f"{first_undecodable_doc(root) or root}: not UTF-8 ({failure.reason})"
        return RepoView(root, query.Repo(root, [], [], []), error, self.web_urls[root])

    def watch(self):
        while not self.stopping.wait(self.poll_seconds):
            try:
                self.poll()
            except Exception as error:  # noqa: BLE001 - one bad scan must not end the watcher
                print(f"plans serve: scan failed: {error!r}", file=sys.stderr)

    def wait_for_version(self, seen, timeout):
        """The version once it differs from `seen`, or `seen` after `timeout` seconds or at shutdown."""
        with self.changed:
            self.changed.wait_for(lambda: self.version != seen or self.stopping.is_set(), timeout)
            return self.version

    def stop(self):
        self.stopping.set()
        with self.changed:
            self.changed.notify_all()

    def find_doc(self, path):
        """The readable doc the board shows at `path`, or None. Writes accept only these paths."""
        for view in self.views.values():
            for doc in view.repo.docs:
                if doc.path == path:
                    return view, doc
        return None, None

    def find_any_doc(self, path):
        """Like find_doc, but also the docs behind error cards, which `o` opens so the owner can fix them."""
        for view in self.views.values():
            for doc in view.repo.docs + view.repo.unreadable + view.repo.old_kind:
                if doc.path == path:
                    return doc
        return None

    def as_json(self):
        with self.changed:
            version, views = self.version, list(self.views.values())
        labels = repo_labels(views)
        views.sort(key=lambda view: (labels[view.root].casefold(), view.root))
        return {
            "version": version,
            "statuses": validate.STATUSES,
            "kinds": validate.KINDS,
            "repos": [view_json(view, labels[view.root]) for view in views],
        }


def holds_dead_owner(view):
    return any(validate.owner_of(doc) is not None and not liveness.owner_is_alive(doc) for doc in view.repo.docs)


def doc_texts(view):
    return view.error, [doc.text for doc in view.repo.docs + view.repo.unreadable + view.repo.old_kind]


def docs_signature(root):
    """What the watcher compares between polls. ctime is in it so a chmod that makes a doc readable again counts."""
    signature = []
    # A conflict copy is no doc, but its arrival or removal changes the board's warnings.
    for path in query.doc_paths(root) + query.conflict_paths(root):
        try:
            stat = os.stat(path)
        except OSError:
            signature.append((path, None))
            continue
        signature.append((path, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns))
    return signature


def first_undecodable_doc(root):
    """The doc that made read_repo fail to decode, which UnicodeDecodeError does not name."""
    for path in query.doc_paths(root):
        try:
            with open(path, "rb") as handle:
                handle.read().decode("utf-8")
        except UnicodeDecodeError:
            return path
        except OSError:
            continue
    return None


def repo_labels(views):
    """The GitHub owner/name of each repo. Without one it is the folder name, with its parent in front on a clash."""
    names = [os.path.basename(view.root) for view in views]
    labels = {}
    for view, name in zip(views, names):
        if view.web_url:
            labels[view.root] = view.web_url.removeprefix("https://github.com/")
        else:
            shared = names.count(name) > 1
            labels[view.root] = f"{os.path.basename(os.path.dirname(view.root))}/{name}" if shared else name
    return labels


def github_web_url(root):
    """https://github.com/<owner>/<repo> from the origin remote, so the page can link a PR number. None off GitHub."""
    result = subprocess.run(["git", "-C", root, "remote", "get-url", "origin"], capture_output=True, text=True)
    remote = result.stdout.strip()
    for prefix in GITHUB_REMOTE_PREFIXES:
        if remote.startswith(prefix):
            slug = remote[len(prefix):].removesuffix("/").removesuffix(".git")
            return "https://github.com/" + slug
    return None


def view_json(view, label):
    repo = view.repo
    problem_docs = [problem_json(doc, "; ".join(f"line {line}: {message}" for line, message in doc.errors))
                    for doc in repo.unreadable]
    problem_docs += [problem_json(doc, f"old kind {doc.keys.get('kind')}; {validate.MIGRATE}") for doc in repo.old_kind]
    if view.error:
        problem_docs.append({"path": view.root, "id": label, "status": None, "error": view.error})
    return {
        "root": view.root,
        "label": label,
        "web_url": view.web_url,
        "docs": [doc_json(doc) for doc in sorted(repo.docs, key=query.rank_order)],
        "problems": problem_docs,
        "conflicts": [{"path": finding.path, "message": finding.message}
                      for finding in validate.conflict_findings(query.conflict_paths(view.root))],
    }


def doc_json(doc):
    data = {key: doc.keys.get(key, parse.DEFAULTS.get(key)) for key in parse.KEY_ORDER}
    # The page sends these back in the basis of an owner edit, so a claim since the page loaded refuses the edit.
    data.update({key: doc.keys.get(key, "") for key in validate.OWNER_VALUE_KEYS})
    data["id"] = doc.id
    data["path"] = doc.path
    # Set for a doc owned on another host. The page shows its card read-only, and the server refuses its writes.
    data["remote_host"] = liveness.owner_host_of(doc) if liveness.is_remote_owned(doc) else ""
    # Lint flags a depends_on that is no list, but the page iterates it, so it always gets one.
    if not isinstance(data["depends_on"], list):
        data["depends_on"] = [] if data["depends_on"] in (None, "") else [str(data["depends_on"])]
    return data


def problem_json(doc, error):
    status = doc.keys.get("status")
    return {"path": doc.path, "id": doc.id, "status": status if status in validate.STATUSES else None, "error": error}


class Handler(http.server.BaseHTTPRequestHandler):
    # Set per server by make_server.
    board = None
    remote = None
    keepalive_seconds = KEEPALIVE_SECONDS

    def log_message(self, format, *args):  # noqa: A002 - the base class names it so
        # The event stream and the page's reloads would fill the journal; errors still print through log_error.
        pass

    def log_error(self, format, *args):  # noqa: A002
        sys.stderr.write("plans serve: " + (format % args) + "\n")

    def local_hosts(self):
        port = self.server.server_address[1]
        return {f"127.0.0.1:{port}", f"localhost:{port}"}

    def is_remote(self):
        """True for a request through `tailscale serve` from the owner's login. The bind is 127.0.0.1, so the header
        only proves the login when nothing but tailscaled can reach the port, the same trust the local board has."""
        remote = self.remote
        if remote is None:
            return False
        host = (self.headers.get("Host") or "").lower()
        logins = self.headers.get_all(LOGIN_HEADER) or []
        return host in {remote.host, f"{remote.host}:443"} and logins == [remote.login]

    def host_refusal(self):
        """The 403 message for a request the Host check turns away, or None when the Host and login pass."""
        # A page on another site can point its own host name at 127.0.0.1 (DNS rebinding). Its requests then carry
        # that name in Host, so checking Host keeps such a page from reading the board.
        if self.headers.get("Host") in self.local_hosts() or self.is_remote():
            return None
        host = (self.headers.get("Host") or "").lower()
        if self.remote and host in {self.remote.host, f"{self.remote.host}:443"}:
            return f"this host needs the tailnet login named in remote.json ({LOGIN_HEADER} through tailscale serve)"
        return "Host must be 127.0.0.1 or localhost"

    def allowed_origins(self):
        if self.is_remote():
            return {f"https://{self.remote.host}"}
        return {f"http://{host}" for host in self.local_hosts()}

    def do_GET(self):  # noqa: N802 - the base class names it so
        refusal = self.host_refusal()
        if refusal:
            return self.send_json(403, {"error": refusal})
        url = urllib.parse.urlsplit(self.path)
        if self.path == "/":
            return self.send_page()
        if self.path == "/api/board":
            return self.send_json(200, self.board.as_json())
        if self.path == "/api/events":
            return self.send_events()
        if url.path == "/api/doc":
            return self.send_doc(urllib.parse.parse_qs(url.query).get("path", [None])[0])
        return self.send_json(404, {"error": f"no page {self.path}"})

    def do_POST(self):  # noqa: N802
        refusal = self.host_refusal()
        if refusal:
            return self.send_json(403, {"error": refusal})
        if not self.write_is_from_board():
            return self.send_json(403, {"error": f"a write needs the {WRITE_HEADER} header and a JSON body"})
        if self.is_remote() and self.path not in REMOTE_ACTIONS:
            return self.send_json(403, {"error": f"{self.path} works on the laptop only"})
        actions = {"/api/update": update_doc, "/api/move": move_doc, "/api/open": open_doc, "/api/cancel": cancel_doc,
                   "/api/toggle": toggle_task, "/api/section": edit_section}
        action = actions.get(self.path)
        if action is None:
            return self.send_json(404, {"error": f"no action {self.path}"})
        code, data = run_action(action, self.board, self.read_json)
        # The page reloads the board right after a write, so the board reads the disk before it answers. A failed
        # read must not cost the page its answer; the watcher tries again.
        try:
            self.board.poll()
        except Exception as error:  # noqa: BLE001
            self.log_error("scan after a write failed: %r", error)
        return self.send_json(code, data)

    def write_is_from_board(self):
        origin = self.headers.get("Origin")
        origin_is_allowed = origin is None or origin in self.allowed_origins()
        is_json = (self.headers.get("Content-Type") or "").split(";")[0].strip() == "application/json"
        return self.headers.get(WRITE_HEADER) == "1" and is_json and origin_is_allowed

    def read_json(self):
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            raise Refused(400, "bad Content-Length") from None
        # A negative length would make rfile.read wait for the client to close the connection.
        if not 0 <= length <= MAX_BODY_BYTES:
            raise Refused(413, f"the body length must be 0 to {MAX_BODY_BYTES} bytes")
        try:
            return json.loads(self.rfile.read(length) or b"null")
        except ValueError:
            raise Refused(400, "the body is no JSON") from None

    def send_doc(self, path):
        """The text of a doc the board shows, error cards included. Any other path is a 404, so this reads no other
        file."""
        doc = self.board.find_any_doc(path)
        if doc is None:
            return self.send_json(404, {"error": f"no doc on the board at {path!r}; reload the board"})
        answer = {"path": doc.path, "text": doc.text}
        if self.board.find_doc(path)[1] is not None:
            # The section editor's starting text and basis. The page cannot cut sections out of the text itself
            # without copying the heading and fence rules of parse.
            answer["sections"] = [{"title": title, "text": text} for title, (_, text) in doc.sections().items()]
        return self.send_json(200, answer)

    def send_page(self):
        with open(PAGE, "rb") as handle:
            body = handle.read()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, code, data):
        body = json.dumps(data).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_events(self):
        """One `version` event now and at each change, and a comment line every keepalive. The comment is also how
        the thread finds out that the page went away: the write fails and the thread ends."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.close_connection = True
        seen = None
        try:
            while not self.board.stopping.is_set():
                version = self.board.wait_for_version(seen, self.keepalive_seconds)
                if version != seen:
                    self.wfile.write(f"event: version\ndata: {version}\n\n".encode())
                    seen = version
                else:
                    self.wfile.write(b": keepalive\n\n")
                self.wfile.flush()
        except OSError:
            pass


def run_action(action, board, read_request):
    """The status code and JSON answer of one write action, with each refusal mapped to its code."""
    try:
        request = read_request()
        if not isinstance(request, dict):
            raise Refused(400, "the body must be a JSON object")
        return 200, action(board, request) or {}
    except Refused as refusal:
        return refusal.code, refusal.data
    except store.Conflict as conflict:
        return 409, {"error": str(conflict), "path": conflict.path, "keys": conflict.keys}
    except store.Vanished as vanished:
        return 410, {"error": str(vanished), "path": vanished.path}
    except parse.ParseError as error:
        return 422, {"error": str(error), "path": error.path}
    except UnicodeDecodeError as error:
        # parse.read decodes before store.update writes anything, so nothing landed.
        return 422, {"error": f"a doc is not UTF-8: {error.reason}"}
    except OSError as error:
        # The failure can come after os.replace (the directory fsync), so the write may have landed.
        return 500, {"error": f"the write failed and may have landed: {error}", "maybe_applied": True}


def board_doc(board, request):
    """The doc a write names, refused when another host owns it."""
    path = request.get("path")
    view, doc = board.find_doc(path)
    if doc is None:
        raise Refused(404, f"no readable doc on the board at {path!r}; reload the board")
    refuse_remote_owned(doc)
    return view, doc


def refuse_remote_owned(doc):
    """Every board write calls this, on the board's copy for a clear early answer and again under the store lock
    (store.update's check_under_lock), where a claim synced in from the other host since the board read shows."""
    if liveness.is_remote_owned(doc):
        raise Refused(403, f"{doc.id} is owned on {liveness.owner_host_of(doc)}; edit it on that host's board")


def based_on(doc, basis):
    """`doc` with the values the page showed for the keys in `basis`. The board's copy can be newer than the page,
    and store.update must compare the disk against what the owner saw, or it would miss an edit made in between."""
    if not isinstance(basis, dict) or any(key not in parse.KEY_ORDER + validate.OWNER_VALUE_KEYS for key in basis):
        raise Refused(400, "basis must map front matter keys to the values the page showed")
    if any(isinstance(value, bool) or not isinstance(value, (str, int)) for value in basis.values()):
        raise Refused(400, "a basis value must be a string or a whole number")
    return parse.Doc(doc.path, doc.render(basis))


def checked_changes(request, allowed_keys):
    changes, basis = request.get("changes"), request.get("basis")
    if not isinstance(changes, dict) or not changes:
        raise Refused(400, "changes must map keys to new values")
    for key, value in changes.items():
        if key not in allowed_keys:
            raise Refused(400, f"the board cannot set {key}")
        problem = validate.write_problem(key, value) if isinstance(value, str) else f"{key} must be a string"
        if problem:
            raise Refused(400, problem)
    if not isinstance(basis, dict) or set(changes) - set(basis):
        raise Refused(400, "basis must hold the shown value of every changed key")
    return changes, basis


def update_doc(board, request):
    """Set status or owner_session. A new owner_session also clears owner_session_id and owner_session_pid.
    Request: {path, basis: {key: shown value}, changes: {key: new value}}."""
    _, doc = board_doc(board, request)
    changes, basis = checked_changes(request, EDITABLE_KEYS)
    if "owner_session" in changes and changes["owner_session"] != basis["owner_session"]:
        # The owner's override: the board knows no session's values, so the next claim writes them. A save under the
        # same name keeps them, or another session of that name could then claim the doc without --force.
        changes = {**changes, **validate.cleared_owner_values()}
    store.update(based_on(doc, basis), changes, check_under_lock=refuse_remote_owned)


def move_doc(board, request):
    """Drop a card into a status column between two neighbours. Request: {path, basis: {status, rank}, status,
    above: path or null, below: path or null}. The new rank is the midpoint of the neighbours' ranks. When they leave
    no gap, the repo's ranks are renumbered in steps of RANK_STEP."""
    view, doc = board_doc(board, request)
    status = request.get("status")
    problem = validate.write_problem("status", status)
    if problem:
        raise Refused(400, problem)
    basis = request.get("basis")
    if not isinstance(basis, dict) or not isinstance(basis.get("rank"), int) or "status" not in basis:
        raise Refused(400, "basis must hold the shown status and rank")
    # The neighbours' ranks come from the disk, not from the page: the drop means "between these two" as they are now.
    repo = query.read_repo(view.root)
    ranked = [other for other in sorted(repo.docs, key=query.rank_order)
              if isinstance(other.keys.get("rank"), int) and other.path != doc.path]
    above, below = (neighbour(ranked, request.get(side)) for side in ("above", "below"))
    refuse_moved_neighbours(ranked, doc, status, above, below)
    if above is None and below is None:
        rank = basis["rank"]
    else:
        rank = rank_between(above and above.keys["rank"], below and below.keys["rank"])
    if rank is not None:
        # Both keys go in even when one keeps the shown value: store.update compares only the keys it writes, and an
        # agent's change to either must refuse the move.
        store.update(based_on(doc, basis), {"status": status, "rank": rank}, check_under_lock=refuse_remote_owned)
        return {"renumbered": 0, "skipped": [], "uncertain": []}
    order = list(ranked)
    order.insert(order.index(below) if below is not None else order.index(above) + 1, doc)
    return renumber(order, doc, based_on(doc, basis), status)


def neighbour(ranked, path):
    if path is None:
        return None
    found = next((other for other in ranked if other.path == path), None)
    if found is None:
        raise Refused(409, f"the card next to the drop at {path} moved or left; reload the board", keys=["rank"])
    return found


def refuse_moved_neighbours(ranked, doc, status, above, below):
    """409 unless `above` and `below` are still next to each other in the target cell (same project and status), with
    nothing before `below` or after `above` when the other side is empty. An agent may have re-ranked or moved them
    since the page loaded, and a drop between them would then renumber over the agent's ranks."""
    cell = [other for other in ranked if other.keys.get("project") == doc.keys.get("project")
            and other.keys.get("status") == status]
    slots = zip([None] + cell, cell + [None])
    if not any(before is above and after is below for before, after in slots):
        raise Refused(409, "the cards around the drop changed since the board loaded; reload the board", keys=["rank"])


def rank_between(above, below):
    """A whole number strictly between the two ranks (None means no card on that side), or None when there is none.
    A rank stays at 0 or above, because the front matter subset has no negative numbers."""
    if above is None:
        return below - RANK_STEP if below >= RANK_STEP else (below // 2 if below > 0 else None)
    if below is None:
        return above + RANK_STEP
    return (above + below) // 2 if below - above >= 2 else None


def renumber(order, moved, moved_basis, status):
    """Give `order` the ranks RANK_STEP, 2 * RANK_STEP and so on. The moved doc goes first, so a stale page refuses the
    whole move. Each other doc is its own store.update: a doc that an agent re-ranked meanwhile keeps the agent's rank
    and lands in `skipped`, as does a doc another host owns. A doc whose write failed partway lands in `uncertain`, and
    the rest are renumbered."""
    new_ranks = {doc.path: RANK_STEP * (index + 1) for index, doc in enumerate(order)}
    store.update(moved_basis, {"status": status, "rank": new_ranks[moved.path]}, check_under_lock=refuse_remote_owned)
    renumbered, skipped, uncertain = 1, [], []
    for doc in order:
        if doc is moved or doc.keys["rank"] == new_ranks[doc.path]:
            continue
        try:
            store.update(doc, {"rank": new_ranks[doc.path]}, check_under_lock=refuse_remote_owned)
            renumbered += 1
        except (store.Conflict, store.Vanished, Refused, parse.ParseError, UnicodeDecodeError) as error:
            skipped.append({"path": doc.path, "id": doc.id, "error": str(error)})
        except OSError as error:
            # As in run_action: the new rank may have landed, so this doc is neither renumbered nor skipped.
            uncertain.append({"path": doc.path, "id": doc.id, "error": str(error)})
    return {"renumbered": renumbered, "skipped": skipped, "uncertain": uncertain}


def toggle_task(board, request):
    """Tick or clear one checkbox in the body. Request: {path, line: the task line as shown, nth: which of the lines
    that read the same (from 0), to: true to tick}. The line is found in the body as on disk, so an edit elsewhere in
    the doc since the page loaded does not refuse the tap. A line that is gone or already shows `to` is a 409."""
    _, doc = board_doc(board, request)
    line, nth, to = request.get("line"), request.get("nth"), request.get("to")
    if not isinstance(line, str) or "\n" in line or "\r" in line:
        raise Refused(400, "line must be the one task line the page showed")
    if isinstance(nth, bool) or not isinstance(nth, int) or nth < 0 or not isinstance(to, bool):
        raise Refused(400, "nth must be a whole number from 0 and to a true or false")

    def flip(body):
        toggled = parse.toggle_line(body, line, nth, to)
        if toggled is None:
            raise Refused(409, f"{doc.id}: that checkbox changed since the board read it", path=doc.path, keys=[parse.BODY])
        return toggled

    store.update_body(doc, flip, check_under_lock=refuse_remote_owned)


def edit_section(board, request):
    """Replace the content of one `## ` section. Request: {path, title, basis_text: the section as the page read it,
    text: the new content}. A section that differs from basis_text on disk is a 409 that carries `current_text`, so
    the page can show it beside the owner's text. The text cannot add or remove a section."""
    _, doc = board_doc(board, request)
    title, basis_text, text = (request.get(key) for key in ("title", "basis_text", "text"))
    if not all(isinstance(value, str) for value in (title, basis_text, text)):
        raise Refused(400, "title, basis_text and text must be strings")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    if len(text.encode("utf-8")) > MAX_SECTION_BYTES:
        raise Refused(413, f"a section holds at most {MAX_SECTION_BYTES // 1024} KiB")
    problem = section_text_problem(text)
    if problem:
        raise Refused(422, problem)
    # One blank line after the heading and a line break at the end, however the page trimmed the text.
    content = "\n" + text.strip("\n") + "\n" if text.strip() else ""

    def replace(body):
        sections = parse.body_sections(body)
        if title not in sections:
            raise Refused(404, f"{doc.id} has no section {title!r} any more; reload the doc")
        current = sections[title][1]
        if current != basis_text:
            raise Refused(409, f"{doc.id}: the section {title} changed since you opened it", path=doc.path,
                          keys=[parse.BODY], current_text=current)
        replaced = parse.replace_section(body, title, content)
        if list(parse.body_sections(replaced)) != list(sections):
            raise Refused(422, "the edit would add or remove a section")
        return replaced

    store.update_body(doc, replace, check_under_lock=refuse_remote_owned)


def section_text_problem(text):
    """Why `text` cannot be one section's content, or None. A `#` or `##` heading would start or end a section, and an
    open fence would hide every heading after it."""
    if "\0" in text:
        return "the text holds a NUL character"
    in_fence = False
    for line in text.splitlines():
        if parse.FENCE.match(line):
            in_fence = not in_fence
        elif not in_fence and parse.HEADING.fullmatch(line):
            return f"a # or ## heading would split the section: {line!r}; use ### inside a section"
    return "a code fence is left open" if in_fence else None


def cancel_doc(board, request):
    """Preview or apply `plans cancel` for one card. Request: {path, basis: {each of retire.GUARDED_KEYS},
    apply: true to run it}. Without `apply: true` nothing changes and the answer lists the changes. A doc that a session
    owns is refused, as `plans cancel` refuses it without --force: set the owner to none with `a` first."""
    view, doc = board_doc(board, request)
    basis = request.get("basis")
    if not isinstance(basis, dict) or set(basis) != set(retire.GUARDED_KEYS):
        raise Refused(400, f"basis must hold the shown {', '.join(retire.GUARDED_KEYS)}")
    shown = based_on(doc, basis)
    # The board's copy can lag the disk. retire.apply compares owner_host on disk against this one.
    refuse_remote_owned(shown)
    owner = validate.owner_of(shown)
    if owner is not None:
        raise Refused(403, f"{shown.id} is owned by {owner}; set the owner to none first")
    try:
        plan = retire.plan(view.root, shown, cancel=True)
    except retire.Refused as error:
        raise Refused(400, str(error)) from None
    answer = {"changes": [step.text for step in plan.steps], "notes": plan.notes}
    if request.get("apply") is not True:
        return answer
    outcome = retire.apply(shown, plan.steps)
    lines = [f"{state}: {text}" for state, text in outcome.lines]
    if outcome.failed:
        raise Refused(502, f"cancel {shown.id} stopped and kept the doc. {'; '.join(lines)}", results=lines)
    return {**answer, "results": lines}


def open_doc(board, request):
    """Open the doc in the editor, in a new terminal window."""
    path = request.get("path")
    doc = board.find_any_doc(path)
    if doc is None:
        raise Refused(404, f"no doc on the board at {path!r}; reload the board")
    try:
        editor = shlex.split(os.environ.get("VISUAL") or os.environ.get("EDITOR") or FALLBACK_EDITOR)
        process = subprocess.Popen([*terminal_command(), *editor, doc.path], cwd=os.path.dirname(doc.path),
                                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   start_new_session=True)
    except ValueError as error:
        raise Refused(500, f"cannot read $VISUAL, $EDITOR or $TERMINAL: {error}") from None
    except OSError as error:
        raise Refused(500, f"cannot start the terminal: {error}") from None
    # Reaps the terminal launcher when it exits, so it leaves no zombie behind.
    threading.Thread(target=process.wait, daemon=True).start()


def terminal_command():
    state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    launcher = os.path.join(state, HYPR_TERMINAL)
    if os.access(launcher, os.X_OK):
        return [launcher, "-e"]
    if os.environ.get("TERMINAL"):
        return [*shlex.split(os.environ["TERMINAL"]), "-e"]
    raise Refused(501, f"no terminal to open the doc in: set $TERMINAL or provide {launcher}")


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True


def make_server(board, port=DEFAULT_PORT, keepalive_seconds=KEEPALIVE_SECONDS, remote=None):
    handler = type("BoardHandler", (Handler,), {"board": board, "keepalive_seconds": keepalive_seconds,
                                                "remote": remote})
    return Server((HOST, port), handler)


def serve(port=DEFAULT_PORT, roots_file=None):
    """Run the board until SIGTERM or SIGINT, then return 0."""
    board = Board(roots_file)
    remote = load_remote()
    httpd = make_server(board, port, remote=remote)
    board.poll(rescan=True)
    watcher = threading.Thread(target=board.watch, name="plans-watcher", daemon=True)
    watcher.start()

    def stop(signum, frame):
        # shutdown() waits for serve_forever to return, and serve_forever runs on this thread, so it runs on another.
        board.stop()
        threading.Thread(target=httpd.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    print(f"plans serve: http://{HOST}:{httpd.server_address[1]}", file=sys.stderr, flush=True)
    if remote:
        print(f"plans serve: https://{remote.host} for {remote.login} through tailscale serve", file=sys.stderr, flush=True)
    try:
        httpd.serve_forever()
    finally:
        board.stop()
        httpd.server_close()
        watcher.join(timeout=5)
    return 0
