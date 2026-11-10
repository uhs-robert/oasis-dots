"""The board's read side: the board JSON, the Host and phone login checks, the doc text, the mtime watcher, the event stream and shutdown."""

import http.client
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.parse

from unittest import mock

sys.dont_write_bytecode = True
PACKAGE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(PACKAGE, ".local", "lib", "plans"))
from plans import liveness, parse, query, roots, server  # noqa: E402
from test_liveness import fake_proc  # noqa: E402

for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
             "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_PREFIX"):
    os.environ.pop(name, None)
ENTRY = os.path.join(PACKAGE, ".local", "bin", "plans")
POLL = 0.05
KEEPALIVE = 0.1


def doc_text(doc_id, rank, project="proj", status="planned", owner="none", waiting_on='""', pr="none"):
    return (f"---\nid: {doc_id}\nproject: {project}\nkind: feature\nstatus: {status}\nowner_session: {owner}\n"
            f"rank: {rank}\ndepends_on: []\nwaiting_on: {waiting_on}\nissue: none\npr: {pr}\nbranch: none\n"
            f"fix_rounds: 0\nupdated: \"2026-11-01\"\n---\n# {doc_id}\n\n## Goal\n\nBody.\n")


def wait_until(condition, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return True
        time.sleep(0.02)
    return False


class Fixture:
    """Temp git repos under one root, a roots file naming it, and a board server on a free port."""

    def __init__(self, test):
        self.temp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self.temp.name, "repos")
        self.roots_file = os.path.join(self.temp.name, "roots")
        with open(self.roots_file, "w", encoding="utf-8") as handle:
            handle.write(self.root + "\n")
        self.test = test
        self.httpd = None
        test.addCleanup(self.temp.cleanup)
        # Pid 100 runs Claude, pid 400 another program.
        self.proc = fake_proc(os.path.join(self.temp.name, "proc"), [100], [400])
        patcher = mock.patch.object(liveness, "PROC_ROOT", self.proc)
        patcher.start()
        test.addCleanup(patcher.stop)

    def repo(self, rel):
        path = os.path.join(self.root, rel)
        os.makedirs(path, exist_ok=True)
        subprocess.run(["git", "init", "-q", "-b", "main", path], check=True)
        return path

    def add(self, repo, doc_id, rank, **keys):
        project = keys.get("project", "proj")
        path = os.path.join(repo, ".plans", project, doc_id + ".md")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(doc_text(doc_id, rank, **keys))
        return path

    def start(self, watch=True, remote=None, laptop_key=None):
        self.board = server.Board(self.roots_file, poll_seconds=POLL)
        self.board.poll(rescan=True)
        self.httpd = server.make_server(self.board, 0, keepalive_seconds=KEEPALIVE, remote=remote, laptop_key=laptop_key)
        self.port = self.httpd.server_address[1]
        self.threads = [threading.Thread(target=self.httpd.serve_forever, daemon=True)]
        self.threads[0].start()
        if watch:
            self.start_watcher()
        self.test.addCleanup(self.stop)

    def start_watcher(self):
        self.watcher = threading.Thread(target=self.board.watch, daemon=True)
        self.threads.append(self.watcher)
        self.watcher.start()

    def stop(self):
        if self.httpd:
            self.board.stop()
            self.httpd.shutdown()
            self.httpd.server_close()
            for thread in self.threads:
                thread.join(5)
            self.httpd = None

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        base = {"Host": f"127.0.0.1:{self.port}"}
        data = None if body is None else json.dumps(body).encode()
        connection.request(method, path, data, {**base, **(headers or {})})
        response = connection.getresponse()
        payload = response.read()
        connection.close()
        return response.status, json.loads(payload) if response.getheader("Content-Type") == "application/json" else payload

    def board_json(self):
        status, data = self.request("GET", "/api/board")
        self.test.assertEqual(status, 200)
        return data

    def open_events(self):
        """A raw socket on the event stream, past the response headers."""
        connection = socket.create_connection(("127.0.0.1", self.port), timeout=5)
        connection.sendall(f"GET /api/events HTTP/1.1\r\nHost: 127.0.0.1:{self.port}\r\n\r\n".encode())
        received = b""
        while b"\r\n\r\n" not in received:
            received += connection.recv(4096)
        return connection, received.split(b"\r\n\r\n", 1)[1]


def read_versions(connection, already=b"", count=1):
    """The data of the next `count` version events on an event stream. Only frames that end in their blank line
    count, so a frame split across two reads is never parsed half-received."""
    received = already

    def whole_version_frames():
        frames = received.split(b"\n\n")[:-1]
        return [frame for frame in frames if b"event: version" in frame]

    while len(whole_version_frames()) < count:
        received += connection.recv(4096)
    return [int(line.split(b": ")[1]) for frame in whole_version_frames()[:count]
            for line in frame.splitlines() if line.startswith(b"data: ")]


class BoardJsonTest(unittest.TestCase):
    def setUp(self):
        self.fixture = Fixture(self)
        self.web = self.fixture.repo("web")
        subprocess.run(["git", "-C", self.web, "remote", "add", "origin", "git@github.com:someone/web.git"], check=True)
        self.alpha_a = self.fixture.repo("a/alpha")
        self.alpha_b = self.fixture.repo("b/alpha")

    def test_docs_come_in_rank_order_with_keys_and_path(self):
        self.fixture.add(self.web, "second", 20, waiting_on='"owner: pick"', pr=12)
        first = self.fixture.add(self.web, "first", 10, project="other", owner="dotfiles-56")
        self.fixture.start()
        web = next(repo for repo in self.fixture.board_json()["repos"] if repo["root"] == self.web)
        self.assertEqual([doc["id"] for doc in web["docs"]], ["first", "second"])
        self.assertEqual(web["docs"][0]["path"], first)
        self.assertEqual(web["docs"][0]["owner_session"], "dotfiles-56")
        self.assertEqual(web["docs"][1]["waiting_on"], "owner: pick")
        self.assertEqual(web["docs"][1]["pr"], 12)
        self.assertEqual(web["web_url"], "https://github.com/someone/web")

    def test_the_board_says_whether_this_host_can_open_a_terminal(self):
        self.fixture.start()
        for display, expected in (("wayland-1", True), (None, False)):
            env = {"WAYLAND_DISPLAY": display} if display else {}
            with mock.patch.dict(os.environ, env):
                if not display:
                    os.environ.pop("WAYLAND_DISPLAY", None)
                self.assertIs(self.fixture.board_json()["can_open_terminal"], expected)

    def test_a_dead_owner_is_freed_on_the_board(self):
        dead = self.fixture.add(self.web, "dead", 10, owner="gone-1")
        live = self.fixture.add(self.web, "live", 20, owner="other-1")
        for path, pid in ((dead, 400), (live, 100)):
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text.replace("updated:", f"owner_session_id: id-a\nowner_session_pid: {pid}\nupdated:"))
        self.fixture.start()
        web = next(repo for repo in self.fixture.board_json()["repos"] if repo["root"] == self.web)
        self.assertEqual([doc["owner_session"] for doc in web["docs"]], ["none", "other-1"])
        self.assertEqual([parse.load(path).keys["owner_session"] for path in (dead, live)], ["none", "other-1"])

    def test_an_owner_that_dies_without_a_file_change_is_freed_at_the_next_poll(self):
        path = self.fixture.add(self.web, "demo", 10, owner="other-1")
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text.replace("updated:", "owner_session_id: id-a\nowner_session_pid: 100\nupdated:"))
        self.fixture.start(watch=False)
        self.fixture.board.poll()
        self.assertEqual(parse.load(path).keys["owner_session"], "other-1")
        shutil.rmtree(os.path.join(self.fixture.proc, "100"))
        self.fixture.board.poll()
        web = next(repo for repo in self.fixture.board_json()["repos"] if repo["root"] == self.web)
        self.assertEqual(web["docs"][0]["owner_session"], "none")
        self.assertEqual(parse.load(path).keys["owner_session"], "none")

    def test_a_dead_owner_that_cannot_be_freed_does_not_bump_the_version(self):
        path = self.fixture.add(self.web, "demo", 10, owner="other-1")
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text.replace("updated:", "owner_session_id: id-a\nowner_session_pid: 400\nupdated:"))
        with mock.patch.object(liveness.store, "replace_atomically", side_effect=PermissionError(13, "denied")):
            self.fixture.start(watch=False)
            version = self.fixture.board.version
            self.fixture.board.poll()
            self.assertEqual(self.fixture.board.version, version)
        self.assertEqual(parse.load(path).keys["owner_session"], "other-1")

    def test_a_repo_without_a_github_remote_keeps_its_folder_label_and_the_parent_on_a_clash(self):
        self.fixture.start()
        labels = {repo["root"]: repo["label"] for repo in self.fixture.board_json()["repos"]}
        self.assertEqual(labels, {self.web: "someone/web", self.alpha_a: "a/alpha", self.alpha_b: "b/alpha"})

    def test_a_repo_with_a_github_remote_is_labelled_owner_slash_name(self):
        subprocess.run(["git", "-C", self.alpha_a, "remote", "add", "origin", "https://github.com/Zoe/renamed.git"], check=True)
        self.fixture.start()
        labels = {repo["root"]: repo["label"] for repo in self.fixture.board_json()["repos"]}
        self.assertEqual(labels[self.alpha_a], "Zoe/renamed")
        self.assertEqual(labels[self.alpha_b], "b/alpha")

    def test_repos_are_listed_by_label_ignoring_case(self):
        subprocess.run(["git", "-C", self.alpha_a, "remote", "add", "origin", "git@github.com:Zoe/alpha.git"], check=True)
        self.fixture.start()
        labels = [repo["label"] for repo in self.fixture.board_json()["repos"]]
        self.assertEqual(labels, ["b/alpha", "someone/web", "Zoe/alpha"])

    def test_a_conflict_copy_is_one_warning_and_no_card(self):
        doc = self.fixture.add(self.web, "good", 10)
        copy = os.path.join(os.path.dirname(doc), "good.sync-conflict-20261109-101500-ABCDEFG.md")
        with open(doc, encoding="utf-8") as source, open(copy, "w", encoding="utf-8") as target:
            target.write(source.read())
        with open(copy, encoding="utf-8") as handle:
            copy_text = handle.read()
        self.fixture.start()
        web = next(repo for repo in self.fixture.board_json()["repos"] if repo["root"] == self.web)
        self.assertEqual([doc["id"] for doc in web["docs"]], ["good"])
        self.assertEqual(web["problems"], [])
        self.assertEqual(web["conflicts"], [{"path": copy, "message": "merge good.md by hand, then delete the copy"}])
        with open(copy, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), copy_text)

    def test_the_signature_changes_when_a_conflict_copy_appears_and_goes(self):
        doc = self.fixture.add(self.web, "good", 10)
        copy = os.path.join(os.path.dirname(doc), "good.sync-conflict-20261109-101500-ABCDEFG.md")
        before = server.docs_signature(self.web)
        with open(copy, "w", encoding="utf-8") as handle:
            handle.write("x\n")
        self.assertNotEqual(server.docs_signature(self.web), before)
        os.remove(copy)
        self.assertEqual(server.docs_signature(self.web), before)

    def test_unreadable_and_old_kind_docs_are_problems(self):
        broken = os.path.join(self.web, ".plans", "proj", "broken.md")
        os.makedirs(os.path.dirname(broken))
        with open(broken, "w", encoding="utf-8") as handle:
            handle.write("---\nid: broken\nstatus: building\nkind: yes\n---\n")
        old = self.fixture.add(self.web, "old", 30)
        with open(old, encoding="utf-8") as handle:
            text = handle.read().replace("kind: feature", "kind: tracker")
        with open(old, "w", encoding="utf-8") as handle:
            handle.write(text)
        self.fixture.start()
        web = next(repo for repo in self.fixture.board_json()["repos"] if repo["root"] == self.web)
        problems = {problem["id"]: problem for problem in web["problems"]}
        self.assertEqual(web["docs"], [])
        self.assertEqual(problems["broken"]["status"], "building")
        self.assertIn("line 4", problems["broken"]["error"])
        self.assertIn("old kind tracker", problems["old"]["error"])

    def test_unreadable_docs_are_per_doc_cards_and_the_good_docs_stay(self):
        self.fixture.add(self.web, "good-a", 10)
        self.fixture.add(self.web, "good-b", 30)
        bad = self.fixture.add(self.web, "bad-utf", 20)
        with open(bad, "wb") as handle:
            handle.write(b"---\nid: bad-utf\n---\n\xff\xfe\n")
        if os.geteuid() != 0:
            locked = self.fixture.add(self.web, "locked", 40)
            os.chmod(locked, 0)
            self.addCleanup(os.chmod, locked, 0o600)
        self.fixture.add(self.alpha_a, "fine", 10)
        self.fixture.start()
        repos = {repo["root"]: repo for repo in self.fixture.board_json()["repos"]}
        web = repos[self.web]
        self.assertEqual([doc["id"] for doc in web["docs"]], ["good-a", "good-b"])
        problems = {problem["id"]: problem for problem in web["problems"]}
        self.assertEqual(problems["bad-utf"]["path"], bad)
        self.assertIn("not UTF-8", problems["bad-utf"]["error"])
        if os.geteuid() != 0:
            self.assertEqual(problems["locked"]["path"], locked)
            self.assertIn("Permission denied", problems["locked"]["error"])
        self.assertEqual([doc["id"] for doc in repos[self.alpha_a]["docs"]], ["fine"])
        self.assertEqual(self.fixture.board.find_any_doc(bad).path, bad)

    def test_a_doc_that_is_not_utf8_is_a_problem_and_the_other_repos_still_read(self):
        bad = self.fixture.add(self.web, "bad", 10)
        with open(bad, "ab") as handle:
            handle.write(b"\xff\xfe")
        self.fixture.add(self.alpha_a, "fine", 10)
        self.fixture.start()
        repos = {repo["root"]: repo for repo in self.fixture.board_json()["repos"]}
        self.assertEqual(repos[self.web]["problems"][0]["path"], bad)
        self.assertIn("not UTF-8", repos[self.web]["problems"][0]["error"])
        self.assertEqual([doc["id"] for doc in repos[self.alpha_a]["docs"]], ["fine"])

    def test_a_depends_on_that_is_no_list_reaches_the_page_as_a_list(self):
        """The page iterates depends_on, and a bare number there threw and blanked every later repo."""
        path = self.fixture.add(self.web, "demo", 10)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text.replace("depends_on: []", "depends_on: 12"))
        self.fixture.start()
        web = next(repo for repo in self.fixture.board_json()["repos"] if repo["root"] == self.web)
        self.assertEqual(web["docs"][0]["depends_on"], ["12"])

    def test_page_is_served(self):
        self.fixture.start()
        status, body = self.fixture.request("GET", "/")
        self.assertEqual(status, 200)
        self.assertIn(b"<title>plans</title>", body)


class RestartTest(unittest.TestCase):
    def test_a_restarted_server_starts_above_the_old_versions(self):
        """An open page drops a board older than the one it shows, so a new server's first board must count as newer."""
        fixture = Fixture(self)
        repo = fixture.repo("web")
        old = server.Board(fixture.roots_file)
        for rank in range(5):
            fixture.add(repo, "demo", rank)
            os.utime(os.path.join(repo, ".plans", "proj", "demo.md"), ns=(time.time_ns(), time.time_ns() + rank))
            old.poll(rescan=True)
        new = server.Board(fixture.roots_file)
        new.poll(rescan=True)
        self.assertGreater(new.version, old.version)
        # The page holds the version in a JavaScript number, exact only up to 2**53.
        self.assertLess(new.version, 2**53)


class HostCheckTest(unittest.TestCase):
    def setUp(self):
        self.fixture = Fixture(self)
        self.fixture.start()

    def test_a_foreign_host_is_refused(self):
        for host in ("evil.example", f"evil.example:{self.fixture.port}", "127.0.0.1:1"):
            for path in ("/", "/api/board", "/api/events"):
                status, data = self.fixture.request("GET", path, headers={"Host": host})
                self.assertEqual(status, 403, (host, path))

    def test_localhost_is_served(self):
        status, _ = self.fixture.request("GET", "/api/board", headers={"Host": f"localhost:{self.fixture.port}"})
        self.assertEqual(status, 200)


PHONE_HOST = "laptop.tail1234.ts.net"
OWNER_LOGIN = "owner@github"
REMOTE = server.Remote(PHONE_HOST, OWNER_LOGIN)
# What a request through `tailscale serve` from the owner's phone carries.
PHONE = {"Host": PHONE_HOST, server.LOGIN_HEADER: OWNER_LOGIN}


class RemoteHostTest(unittest.TestCase):
    """The MagicDNS name works only with remote.json and only for the owner's tailnet login."""

    def setUp(self):
        self.fixture = Fixture(self)

    def get(self, path, headers):
        return self.fixture.request("GET", path, headers=headers)[0]

    def test_the_owner_through_tailscale_serve_is_served(self):
        self.fixture.start(remote=REMOTE)
        for headers in (PHONE, {**PHONE, "Host": PHONE_HOST.upper() + ":443"}):
            for path in ("/", "/api/board"):
                self.assertEqual(self.get(path, headers), 200, (headers, path))

    def test_without_the_config_the_phone_host_is_refused(self):
        self.fixture.start()
        status, data = self.fixture.request("GET", "/api/board", headers=PHONE)
        self.assertEqual((status, data["error"]), (403, "Host must be 127.0.0.1 or localhost"))

    def test_a_missing_wrong_or_doubled_login_is_refused(self):
        self.fixture.start(remote=REMOTE)
        for login in (None, "", "someone@github", OWNER_LOGIN.upper(), OWNER_LOGIN + " "):
            headers = {"Host": PHONE_HOST} if login is None else {**PHONE, server.LOGIN_HEADER: login}
            for path in ("/", "/api/board", "/api/events"):
                self.assertEqual(self.get(path, headers), 403, (login, path))
            # The owner with a typo in remote.json learns that the login failed, not the Host.
            self.assertIn("tailnet login", self.fixture.request("GET", "/api/board", headers=headers)[1]["error"])
        connection = http.client.HTTPConnection("127.0.0.1", self.fixture.port, timeout=5)
        connection.putrequest("GET", "/api/board", skip_host=True)
        for name, value in (("Host", PHONE_HOST), (server.LOGIN_HEADER, "someone@github"),
                            (server.LOGIN_HEADER, OWNER_LOGIN)):
            connection.putheader(name, value)
        connection.endheaders()
        self.assertEqual(connection.getresponse().status, 403)
        connection.close()

    def test_the_owner_login_does_not_open_another_host(self):
        self.fixture.start(remote=REMOTE)
        for host in ("evil.example", f"{PHONE_HOST}.evil.example", f"{PHONE_HOST}:8443", "other.tail1234.ts.net"):
            self.assertEqual(self.get("/api/board", {**PHONE, "Host": host}), 403, host)

    def test_the_local_hosts_still_work_with_the_config(self):
        self.fixture.start(remote=REMOTE)
        self.assertEqual(self.get("/api/board", {}), 200)


class LoadRemoteTest(unittest.TestCase):
    def config(self, text):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        path = os.path.join(temp.name, "remote.json")
        if text is not None:
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text)
        return path

    def test_a_full_config_names_the_host_and_login_without_the_root_dot(self):
        path = self.config(json.dumps({"host": "Laptop.tail1234.ts.net.", "login": OWNER_LOGIN}))
        self.assertEqual(server.load_remote(path), REMOTE)

    def test_no_file_keeps_remote_off_quietly(self):
        with mock.patch("sys.stderr") as stderr:
            self.assertIsNone(server.load_remote(self.config(None)))
        stderr.write.assert_not_called()

    def test_a_broken_or_partial_file_keeps_remote_off_and_says_so(self):
        for text in ("{", "[]", '{"host": "laptop.tail1234.ts.net"}', '{"host": "", "login": "owner@github"}',
                     '{"host": "laptop.tail1234.ts.net", "login": 5}'):
            with mock.patch("sys.stderr") as stderr:
                self.assertIsNone(server.load_remote(self.config(text)), text)
            self.assertIn("remote access stays off", "".join(call.args[0] for call in stderr.write.call_args_list))

    def test_the_file_lives_under_xdg_config_home(self):
        path = self.config(json.dumps({"host": PHONE_HOST, "login": OWNER_LOGIN}))
        with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": os.path.dirname(os.path.dirname(path))}):
            self.assertEqual(server.remote_config_file(), os.path.join(os.path.dirname(os.path.dirname(path)), "plans", "remote.json"))


class DocEndpointTest(unittest.TestCase):
    def setUp(self):
        self.fixture = Fixture(self)
        self.repo = self.fixture.repo("web")

    def doc(self, path, headers=None):
        query = urllib.parse.urlencode({"path": path})
        return self.fixture.request("GET", f"/api/doc?{query}", headers=headers)

    def test_a_card_returns_its_doc_text(self):
        path = self.fixture.add(self.repo, "demo", 10)
        self.fixture.start()
        status, data = self.doc(path)
        self.assertEqual(status, 200)
        self.assertEqual(data, {"path": path, "text": doc_text("demo", 10),
                                "sections": [{"title": "Goal", "text": "\nBody.\n"}]})

    def test_an_error_card_returns_its_text_too(self):
        path = os.path.join(self.repo, ".plans", "proj", "broken.md")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("---\nid: broken\nnested:\n  key: 1\n---\n")
        self.fixture.start()
        status, data = self.doc(path)
        self.assertEqual((status, data["text"]), (200, "---\nid: broken\nnested:\n  key: 1\n---\n"))

    def test_a_path_off_the_board_is_not_read(self):
        self.fixture.add(self.repo, "demo", 10)
        self.fixture.start()
        outside = os.path.join(self.fixture.temp.name, "roots")
        for path in (outside, os.path.join(self.repo, ".plans", "proj", "..", "..", ".git", "config"), ""):
            status, data = self.doc(path)
            self.assertEqual(status, 404, path)
            self.assertNotIn("text", data)
        self.assertEqual(self.fixture.request("GET", "/api/doc")[0], 404)

    def test_the_doc_follows_the_host_check(self):
        path = self.fixture.add(self.repo, "demo", 10)
        self.fixture.start(remote=REMOTE)
        self.assertEqual(self.doc(path, {"Host": "evil.example"})[0], 403)
        self.assertEqual(self.doc(path, {"Host": PHONE_HOST})[0], 403)
        self.assertEqual(self.doc(path, PHONE)[0], 200)


class WatcherTest(unittest.TestCase):
    def setUp(self):
        self.fixture = Fixture(self)
        self.repo = self.fixture.repo("web")
        self.path = self.fixture.add(self.repo, "demo", 10)

    def docs(self):
        return {doc["id"]: doc for repo in self.fixture.board_json()["repos"] for doc in repo["docs"]}

    def problems(self):
        return [problem for repo in self.fixture.board_json()["repos"] for problem in repo["problems"]]

    def test_an_edit_on_disk_reaches_the_event_stream(self):
        self.fixture.start()
        connection, rest = self.fixture.open_events()
        self.addCleanup(connection.close)
        [first] = read_versions(connection, rest)
        self.fixture.add(self.repo, "demo", 10, status="building")
        received = b""
        while b"event: version" not in received:
            received += connection.recv(4096)
        [second] = read_versions(connection, received)
        self.assertGreater(second, first)
        self.assertEqual(self.docs()["demo"]["status"], "building")

    def test_a_new_repo_shows_after_the_rescan(self):
        self.fixture.start()
        self.fixture.board.rescan_seconds = POLL
        other = self.fixture.repo("other")
        self.fixture.add(other, "late", 10)
        self.assertTrue(wait_until(lambda: "late" in self.docs()))

    def test_a_doc_deleted_or_renamed_mid_scan_is_read_again(self):
        # No watcher yet: a concurrent poll would read the touched repo before the patch and leave nothing to inject.
        self.fixture.start(watch=False)
        renamed = os.path.join(os.path.dirname(self.path), "moved.md")
        real_read = parse.read
        for current, change in ((self.path, lambda: os.rename(self.path, renamed)), (renamed, lambda: os.unlink(renamed))):
            # A newer mtime makes the poll read the repo again, and the read then meets the change.
            os.utime(current, ns=(time.time_ns(), time.time_ns() + 10**9))
            calls = []

            def read_after_change(path, change=change, calls=calls):
                if not calls:
                    calls.append(path)
                    change()
                return real_read(path)

            with mock.patch.object(parse, "read", read_after_change):
                self.fixture.board.poll(rescan=True)
            self.assertTrue(calls)
            self.assertEqual(self.problems(), [])
        self.assertEqual(self.docs(), {})
        self.fixture.start_watcher()
        time.sleep(POLL * 3)
        self.assertTrue(self.fixture.watcher.is_alive())

    @unittest.skipIf(os.geteuid() == 0, "root reads a file without read permission")
    def test_a_doc_without_read_permission_is_a_problem_until_fixed(self):
        self.fixture.start()
        os.chmod(self.path, 0)
        self.addCleanup(os.chmod, self.path, 0o644)
        self.assertTrue(wait_until(lambda: self.problems()))
        self.assertIn("Permission denied", self.problems()[0]["error"])
        os.chmod(self.path, 0o644)
        self.assertTrue(wait_until(lambda: not self.problems() and "demo" in self.docs()))

    def test_the_watcher_survives_a_failed_scan(self):
        self.fixture.start()
        with mock.patch.object(roots, "all_repos", side_effect=RuntimeError("boom")), \
                mock.patch.object(sys, "stderr"):
            self.fixture.board.rescan_seconds = 0
            time.sleep(POLL * 5)
        self.assertTrue(self.fixture.watcher.is_alive())
        self.fixture.add(self.repo, "demo", 10, status="done")
        self.assertTrue(wait_until(lambda: self.docs()["demo"]["status"] == "done"))


class EventStreamTest(unittest.TestCase):
    def test_closed_streams_end_their_threads(self):
        fixture = Fixture(self)
        fixture.repo("web")
        fixture.start()
        baseline = threading.active_count()
        streams = [fixture.open_events() for _ in range(20)]
        for connection, rest in streams:
            read_versions(connection, rest)
        self.assertGreaterEqual(threading.active_count(), baseline + 20)
        for connection, _ in streams:
            connection.close()
        # Each thread notices at its next keepalive write. The first write after a close can still succeed, so
        # allow a few rounds.
        self.assertTrue(wait_until(lambda: threading.active_count() <= baseline, timeout=KEEPALIVE * 40))
        status, _ = fixture.request("GET", "/api/board")
        self.assertEqual(status, 200)

    def test_stop_ends_open_streams(self):
        fixture = Fixture(self)
        fixture.repo("web")
        fixture.start()
        connection, rest = fixture.open_events()
        self.addCleanup(connection.close)
        read_versions(connection, rest)
        fixture.board.stop()
        received = b""
        while True:
            chunk = connection.recv(4096)
            if not chunk:
                break
            received += chunk
        self.assertNotIn(b"event: version", received)


class ShutdownTest(unittest.TestCase):
    def test_sigterm_exits_cleanly_with_a_stream_open(self):
        fixture = Fixture(self)
        fixture.add(fixture.repo("web"), "demo", 10)
        port = free_port()
        config = os.path.join(fixture.temp.name, "config")
        os.makedirs(os.path.join(config, "plans"))
        os.symlink(fixture.roots_file, os.path.join(config, "plans", "roots"))
        process = subprocess.Popen([sys.executable, "-B", ENTRY, "serve", "--port", str(port)],
                                   env={**os.environ, "XDG_CONFIG_HOME": config}, stderr=subprocess.PIPE, text=True)
        self.addCleanup(process.stderr.close)
        self.addCleanup(lambda: process.poll() is None and process.kill())
        self.assertIn(f"127.0.0.1:{port}", process.stderr.readline())
        fixture.port = port
        connection, rest = fixture.open_events()
        self.addCleanup(connection.close)
        read_versions(connection, rest)
        process.send_signal(signal.SIGTERM)
        self.assertEqual(process.wait(timeout=10), 0)
        self.assertEqual(process.stderr.read(), "")

    def home(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        return temp.name

    def test_a_taken_port_is_a_usage_error(self):
        holder = socket.socket()
        holder.bind(("127.0.0.1", 0))
        holder.listen()
        self.addCleanup(holder.close)
        result = subprocess.run([sys.executable, "-B", ENTRY, "serve", "--port", str(holder.getsockname()[1])],
                                capture_output=True, text=True, timeout=30,
                                env={**os.environ, "HOME": self.home(), "XDG_CONFIG_HOME": self.home()})
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("cannot serve", result.stderr)


def free_port():
    probe = socket.socket()
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    return port


if __name__ == "__main__":
    unittest.main()
