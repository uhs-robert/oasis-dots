#!/usr/bin/env bash
# Runs scripts/window-cwd against a stubbed `tmux` and real throwaway processes on a pty: the tmux client is picked by
# tty before the title, and the `tmux: client` process is never named as an app.
set -u
here=$(cd "$(dirname "$0")" && pwd)
exec python3 -I - "$here/../../.config/quickshell/scripts/window-cwd" <<'PY'
import ctypes, os, pty, signal, subprocess, sys, tempfile, time

script = os.path.realpath(sys.argv[1])
work = tempfile.mkdtemp()
stub_dir = os.path.join(work, "bin")
os.mkdir(stub_dir)
clients_file = os.path.join(work, "clients")
# list-clients prints whatever the test wrote, in window-cwd's format: client_pid, session, path, pane_pid, client_tty.
with open(os.path.join(stub_dir, "tmux"), "w") as f:
    f.write('#!/bin/sh\n[ "$1" = list-clients ] && cat "%s"\nexit 0\n' % clients_file)
os.chmod(os.path.join(stub_dir, "tmux"), 0o755)
env = dict(os.environ, PATH=stub_dir + ":" + os.environ["PATH"], XDG_RUNTIME_DIR=work)

def run_script(window_pid, title):
    return subprocess.run([script, str(window_pid), title, "1"], env=env, capture_output=True, text=True, timeout=20).stdout.strip()

def read_line(fd):
    buf = b""
    while not buf.endswith(b"\n"):
        buf += os.read(fd, 1)
    return buf.decode().strip()

failed = 0
total = 0
def check(name, got, want):
    global failed, total
    total += 1
    if got != want:
        failed += 1
        print("FAIL %s\n  want: %r\n  got:  %r" % (name, want, got))

windows = []
def spawn_window(body):
    pid, fd = pty.fork()
    if pid == 0:
        body()
        os._exit(0)
    windows.append(pid)
    return pid, fd

# Two tmux clients under one window pid, the first one on another tty, and a title naming neither session.
def two_clients():
    os.execvp("bash", ["bash", "-c", "sleep 60 & echo $!; sleep 60 & echo $!; wait"])
pid, fd = spawn_window(two_clients)
other_client, own_client = int(read_line(fd)), int(read_line(fd))
tty = subprocess.run(["ps", "-o", "tty=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
with open(clients_file, "w") as f:
    f.write("%d\ta\t/tmp/other\t%d\t/dev/pts/99999\n" % (other_client, other_client))
    f.write("%d\tb\t/tmp/own\t%d\t/dev/%s\n" % (own_client, own_client, tty))
check("client on the window's tty wins over a title that matches neither", run_script(pid, "unrelated"), "/tmp/own")

def write_clients(*rows):
    with open(clients_file, "w") as f:
        for row in rows:
            f.write("%d\t%s\t%s\t%d\t%s\n" % row)

# Plain `tmux attach` from the window's shell: one client, a child of the window on its tty.
write_clients((own_client, "b", "/tmp/own", own_client, "/dev/" + tty))
check("a sole client on the window's tty is picked whatever the title", run_script(pid, "unrelated"), "/tmp/own")
# Clients that merely descend from the window pid (no tty match) rank equal, so the title decides.
write_clients((other_client, "a", "/tmp/a", other_client, "/dev/pts/99998"), (own_client, "b", "/tmp/b", own_client, "/dev/pts/99999"))
check("the title picks between clients of equal rank", run_script(pid, "b"), "/tmp/b")
check("the title picks the other client too", run_script(pid, "Tmux a"), "/tmp/a")
# No title match and no better rank: no tmux path, rather than a guess between the two.
check("ambiguous clients give no answer", run_script(pid, "unrelated"), "")
# The title, with its layout prefix and the program after the session name, picks the session.
write_clients((other_client, "Other", "/tmp/other", other_client, "/dev/pts/99999"), (own_client, "Config", "/tmp/config", own_client, "/dev/pts/99998"))
check("title 'Tmux <session> <program>' picks that session's client", run_script(pid, "Tmux Config nvim"), "/tmp/config")
check("title '<session> <program>' picks that session's client", run_script(pid, "Config nvim"), "/tmp/config")

# A window whose only child shell is the tmux client process: its comm is `tmux: client`, which is not an app.
open(clients_file, "w").close()
cwd = os.path.join(work, "client_cwd")
os.mkdir(cwd)
def client_with_child():
    ctypes.CDLL(None).prctl(15, b"tmux: client")
    if os.fork() == 0:
        os.chdir(cwd)
        os.execvp("sleep", ["sleep", "60"])
    time.sleep(60)
pid, fd = spawn_window(client_with_child)
time.sleep(0.5)
check("tmux: client is not named as an app", run_script(pid, "t"), os.path.realpath(cwd))

for w in windows:
    try:
        os.killpg(w, signal.SIGKILL)
    except OSError:
        pass
print("%d/%d passed" % (total - failed, total))
sys.exit(1 if failed else 0)
PY
