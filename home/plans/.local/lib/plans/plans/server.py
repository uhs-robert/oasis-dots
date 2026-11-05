"""`plans serve`: one local web board over the plan docs of every repo under the roots.

The board reads each repo through query.read_repo, so it sees what `plans ls --all` sees. A watcher thread polls the doc
mtimes and pushes a new board version to the page by server-sent events.
"""

import http.server
import json
import os
import signal
import subprocess
import sys
import threading
import time

from typing import NamedTuple

from . import parse, query, roots, validate

HOST = "127.0.0.1"
DEFAULT_PORT = 8765
POLL_SECONDS = 1
RESCAN_SECONDS = 30
KEEPALIVE_SECONDS = 15
PAGE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "board.html")
GITHUB_REMOTE_PREFIXES = ("git@github.com:", "https://github.com/", "ssh://git@github.com/")


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
                if root in self.views and self.signatures.get(root) == signatures[root]:
                    views[root] = self.views[root]
                    continue
                views[root] = self.read_view(root)
                changed = True
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
                return RepoView(root, query.read_repo(root), None, self.web_urls[root])
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

    def as_json(self):
        with self.changed:
            version, views = self.version, list(self.views.values())
        labels = repo_labels([view.root for view in views])
        return {
            "version": version,
            "statuses": validate.STATUSES,
            "kinds": validate.KINDS,
            "repos": [view_json(view, labels[view.root]) for view in views],
        }


def docs_signature(root):
    """What the watcher compares between polls. ctime is in it so a chmod that makes a doc readable again counts."""
    signature = []
    for path in query.doc_paths(root):
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


def repo_labels(repo_roots):
    """The folder name of each repo, with its parent folder in front when two repos share the name."""
    names = [os.path.basename(root) for root in repo_roots]
    labels = {}
    for root, name in zip(repo_roots, names):
        shared = names.count(name) > 1
        labels[root] = f"{os.path.basename(os.path.dirname(root))}/{name}" if shared else name
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
    }


def doc_json(doc):
    data = {key: doc.keys.get(key, parse.DEFAULTS.get(key)) for key in parse.KEY_ORDER}
    data["id"] = doc.id
    data["path"] = doc.path
    return data


def problem_json(doc, error):
    status = doc.keys.get("status")
    return {"path": doc.path, "id": doc.id, "status": status if status in validate.STATUSES else None, "error": error}


class Handler(http.server.BaseHTTPRequestHandler):
    # Set per server by make_server.
    board = None
    keepalive_seconds = KEEPALIVE_SECONDS

    def log_message(self, format, *args):  # noqa: A002 - the base class names it so
        # The event stream and the page's reloads would fill the journal; errors still print through log_error.
        pass

    def log_error(self, format, *args):  # noqa: A002
        sys.stderr.write("plans serve: " + (format % args) + "\n")

    def allowed_hosts(self):
        port = self.server.server_address[1]
        return {f"127.0.0.1:{port}", f"localhost:{port}"}

    def host_is_local(self):
        # A page on another site can point its own host name at 127.0.0.1 (DNS rebinding). Its requests then carry
        # that name in Host, so checking Host keeps such a page from reading the board.
        return self.headers.get("Host") in self.allowed_hosts()

    def do_GET(self):  # noqa: N802 - the base class names it so
        if not self.host_is_local():
            return self.send_json(403, {"error": "Host must be 127.0.0.1 or localhost"})
        if self.path == "/":
            return self.send_page()
        if self.path == "/api/board":
            return self.send_json(200, self.board.as_json())
        if self.path == "/api/events":
            return self.send_events()
        return self.send_json(404, {"error": f"no page {self.path}"})

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


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True


def make_server(board, port=DEFAULT_PORT, keepalive_seconds=KEEPALIVE_SECONDS):
    handler = type("BoardHandler", (Handler,), {"board": board, "keepalive_seconds": keepalive_seconds})
    return Server((HOST, port), handler)


def serve(port=DEFAULT_PORT, roots_file=None):
    """Run the board until SIGTERM or SIGINT, then return 0."""
    board = Board(roots_file)
    httpd = make_server(board, port)
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
    try:
        httpd.serve_forever()
    finally:
        board.stop()
        httpd.server_close()
        watcher.join(timeout=5)
    return 0
