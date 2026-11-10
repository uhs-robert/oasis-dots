"""The laptop key: its file, and the gate it opens for /api/open and /api/cancel on the tailnet address."""

import http.client
import io
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

from unittest import mock

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from test_server import PHONE, PHONE_HOST, REMOTE, Fixture  # noqa: E402
from test_server_writes import WRITE, WriteTest  # noqa: E402

from plans import server  # noqa: E402

KEY = "k" * 43
LAPTOP_ONLY = ("/api/open", "/api/cancel")


class LaptopKeyFileTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.dir = os.path.join(temp.name, "state", "plans")
        self.path = os.path.join(self.dir, "laptop-key")

    def load(self):
        stderr = io.StringIO()
        with mock.patch("sys.stderr", stderr):
            key = server.load_laptop_key(self.path)
        return key, stderr.getvalue()

    def test_the_first_load_creates_a_private_key_and_later_loads_keep_it(self):
        old = os.umask(0o022)
        try:
            key, said = self.load()
        finally:
            os.umask(old)
        self.assertRegex(key, r"^[A-Za-z0-9_-]{43}$")
        self.assertEqual(said, "")
        self.assertEqual(stat.S_IMODE(os.stat(self.path).st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(os.stat(self.dir).st_mode), 0o700)
        self.assertEqual(os.listdir(self.dir), ["laptop-key"])
        self.assertEqual(self.load(), (key, ""))

    def test_a_key_another_writer_placed_first_wins(self):
        real_link = os.link

        def racing_link(source, target):
            with open(target, "w", encoding="ascii") as handle:
                handle.write(KEY + "\n")
            os.chmod(target, 0o600)
            return real_link(source, target)

        os.makedirs(self.dir)
        with mock.patch("os.link", racing_link):
            self.assertEqual(self.load()[0], KEY)
        self.assertEqual(os.listdir(self.dir), ["laptop-key"])

    def test_a_bad_file_turns_the_key_off_without_naming_its_text(self):
        os.makedirs(self.dir)
        secret_ish = "s" * 40
        for text, mode in ((secret_ish + "\n", 0o600), (KEY + "\n", 0o644), ("\xff" * 43, 0o600)):
            with self.subTest(text=text[:3], mode=oct(mode)):
                with open(self.path, "w", encoding="latin-1") as handle:
                    handle.write(text)
                os.chmod(self.path, mode)
                key, said = self.load()
                self.assertIsNone(key)
                self.assertIn("the laptop key is off", said)
                self.assertNotIn(text.strip(), said)

    @unittest.skipIf(os.geteuid() == 0, "root reads any file")
    def test_an_unreadable_file_turns_the_key_off(self):
        os.makedirs(self.dir)
        with open(self.path, "w", encoding="ascii") as handle:
            handle.write(KEY + "\n")
        os.chmod(self.path, 0)
        key, said = self.load()
        self.assertIsNone(key)
        self.assertIn("the laptop key is off", said)
        self.assertNotIn(KEY, said)

    @unittest.skipIf(os.geteuid() == 0, "root writes anywhere")
    def test_an_unwritable_directory_turns_the_key_off(self):
        os.makedirs(self.dir)
        os.chmod(self.dir, 0o500)
        self.addCleanup(os.chmod, self.dir, 0o700)
        self.assertIsNone(self.load()[0])

    def test_the_file_lives_under_xdg_state_home(self):
        with mock.patch.dict(os.environ, {"XDG_STATE_HOME": "/x/state"}):
            self.assertEqual(server.laptop_key_file(), "/x/state/plans/laptop-key")


class LaptopKeyGateTest(WriteTest):
    def setUp(self):
        super().setUp()
        self.path = self.add("demo", 10)
        self.laptop = {**PHONE, "Origin": f"https://{PHONE_HOST}"}
        self.stderr = io.StringIO()
        patcher = mock.patch("sys.stderr", self.stderr)
        patcher.start()
        self.addCleanup(patcher.stop)

    # The cancel here has an empty basis: past the gate it is a 400 about the basis, so it changes nothing and still
    # shows the gate let it through.
    def open_and_cancel(self, headers, start=True, **start_args):
        if start:
            self.fixture.start(**{"remote": REMOTE, "laptop_key": KEY, **start_args})
        environment = {"TERMINAL": "term", "XDG_STATE_HOME": self.fixture.temp.name}
        with mock.patch.dict(os.environ, environment), mock.patch.object(server.subprocess, "Popen") as popen:
            opened = self.post("open", {"path": self.path}, headers)
            cancelled = self.post("cancel", {"path": self.path, "basis": {}, "apply": False}, headers)
        return opened, cancelled, popen

    def assert_refused(self, answers):
        opened, cancelled, popen = answers
        for status, data in (opened, cancelled):
            self.assertEqual(status, 403)
            self.assertIn("open the board from the laptop launcher (Super+A, then K)", data["error"])
        popen.assert_not_called()

    def test_without_the_key_both_are_refused(self):
        self.assert_refused(self.open_and_cancel(self.laptop))

    def test_a_wrong_doubled_or_odd_key_is_refused(self):
        self.fixture.start(remote=REMOTE, laptop_key=KEY)
        for sent in ("", KEY[:-1], KEY + "k", KEY.upper(), "\xe9" * 43):
            with self.subTest(sent=sent[:4]):
                self.assert_refused(self.open_and_cancel({**self.laptop, server.LAPTOP_KEY_HEADER: sent}, start=False))

    def test_a_doubled_header_is_refused_even_with_the_key(self):
        self.fixture.start(remote=REMOTE, laptop_key=KEY)
        connection = http.client.HTTPConnection("127.0.0.1", self.fixture.port, timeout=5)
        body = b'{"path": "x"}'
        connection.putrequest("POST", "/api/open", skip_host=True)
        for name, value in [*{**self.laptop, **WRITE}.items(), (server.LAPTOP_KEY_HEADER, KEY),
                            (server.LAPTOP_KEY_HEADER, KEY), ("Content-Length", str(len(body)))]:
            connection.putheader(name, value)
        connection.endheaders(body)
        self.assertEqual(connection.getresponse().status, 403)
        connection.close()

    def test_a_server_without_a_key_refuses_every_key(self):
        self.assert_refused(self.open_and_cancel({**self.laptop, server.LAPTOP_KEY_HEADER: KEY}, laptop_key=None))
        self.assert_refused(self.open_and_cancel({**self.laptop, server.LAPTOP_KEY_HEADER: ""}, start=False))

    def test_the_key_opens_both_and_appears_in_no_answer_or_log(self):
        (status, data), (cancel_status, cancel_data), popen = self.open_and_cancel(
            {**self.laptop, server.LAPTOP_KEY_HEADER: KEY})
        self.assertEqual((status, cancel_status), (200, 400), (data, cancel_data))
        self.assertIn("basis must hold", cancel_data["error"])
        popen.assert_called_once()
        self.assertNotIn(KEY, str(popen.call_args))
        self.assertNotIn(KEY, repr((data, cancel_data)))
        # A refused and a 404 write answer without the key too.
        for path in ("/api/nothing", "/api/open"):
            sent = KEY if path == "/api/nothing" else KEY[:-1] + "x"
            status, data = self.fixture.request("POST", path, {"path": self.path},
                                                {**WRITE, **self.laptop, server.LAPTOP_KEY_HEADER: sent})
            self.assertNotIn(KEY[:20], repr(data))
        _, page = self.fixture.request("GET", "/", headers=self.laptop)
        self.assertNotIn(KEY.encode(), page)
        self.assertNotIn(KEY, repr(self.fixture.board_json()))
        self.assertNotIn(KEY[:20], self.stderr.getvalue())

    def test_the_key_never_opens_the_tailnet_host_for_another_login(self):
        self.fixture.start(remote=REMOTE, laptop_key=KEY)
        stranger = {**self.laptop, server.LOGIN_HEADER: "someone@github", server.LAPTOP_KEY_HEADER: KEY}
        opened, cancelled, popen = self.open_and_cancel(stranger, start=False)
        self.assertEqual((opened[0], cancelled[0]), (403, 403))
        self.assertIn("tailnet login", opened[1]["error"])
        popen.assert_not_called()

    def test_local_requests_need_no_key(self):
        (status, _), (cancel_status, data), popen = self.open_and_cancel({})
        self.assertEqual((status, cancel_status), (200, 400))
        self.assertIn("basis must hold", data["error"])
        popen.assert_called_once()

    def test_the_phone_actions_need_no_key(self):
        self.assertEqual(server.REMOTE_ACTIONS, ("/api/update", "/api/move", "/api/toggle", "/api/section"))
        self.fixture.start(remote=REMOTE, laptop_key=KEY)
        body = {"path": self.path, "basis": {"status": "planned"}, "changes": {"status": "building"}}
        self.assertEqual(self.post("update", body, self.laptop)[0], 200)


class ServeKeyTest(unittest.TestCase):
    """`plans serve` writes the key only when remote.json opens the tailnet address."""

    def run_serve(self, remote):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        made = {}

        def fake_make_server(board, port, remote=None, laptop_key=None):
            made["key"] = laptop_key
            raise SystemExit

        with mock.patch.dict(os.environ, {"XDG_STATE_HOME": temp.name}), \
                mock.patch.object(server, "load_remote", return_value=remote), \
                mock.patch.object(server, "make_server", fake_make_server), \
                mock.patch.object(server, "Board"), self.assertRaises(SystemExit):
            server.serve()
        return made["key"], os.path.join(temp.name, "plans", "laptop-key")

    def test_with_remote_the_key_is_written_and_handed_to_the_server(self):
        key, path = self.run_serve(REMOTE)
        with open(path, encoding="ascii") as handle:
            self.assertEqual(handle.read().strip(), key)

    def test_without_remote_no_key_is_written(self):
        key, path = self.run_serve(None)
        self.assertIsNone(key)
        self.assertFalse(os.path.exists(path))


@unittest.skipUnless(shutil.which("node"), "the fragment test needs node")
class BoardFragmentTest(unittest.TestCase):
    def test_the_page_takes_and_strips_the_fragment(self):
        result = subprocess.run(["node", os.path.join(HERE, "laptop_key.test.mjs")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
