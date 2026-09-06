#!/usr/bin/env python3
"""Bootstrap regression tests: real Stow/OpenSSH, mocked Android-only commands."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

SOURCE = Path(__file__).resolve().parents[1]
REAL_GIT = shutil.which('git')
REAL_KEYGEN = shutil.which('ssh-keygen')


def run(args, env, success=True):
    result = subprocess.run(args, env=env, text=True, capture_output=True)
    assert (result.returncode == 0) == success, result.stdout + result.stderr
    return result


def executable(path, body):
    path.write_text('#!/usr/bin/env bash\nset -e\n' + body)
    path.chmod(0o755)


with tempfile.TemporaryDirectory(prefix='termux test ') as temporary:
    root = Path(temporary)
    checkout = root / 'checkout' / 'termux'
    shutil.copytree(SOURCE, checkout)
    prefix = root / 'prefix'
    bins = prefix / 'bin'
    bins.mkdir(parents=True)
    for name in ('pkg', 'chsh', 'termux-reload-settings', 'ya', 'nvim'):
        executable(bins / name, 'printf "%s\\n" "$0 $*" >> "$HOME/calls"\n')
    executable(bins / 'apt-cache', 'exit 100\n')
    executable(bins / 'curl', r'''while (( $# )); do
    if [[ $1 == --output ]]; then
        case ${FONT_DOWNLOAD_MODE:-valid} in
            failed) printf partial > "$2"; exit 18 ;;
            invalid) printf '<html>error</html>' > "$2"; exit 0 ;;
        esac
        printf '\000\001\000\000mock-font-data' > "$2"
        exit 0
    fi
    shift
done
exit 1
''')
    executable(bins / 'git', '''if [[ $1 == clone ]]; then
    destination=${@: -1}
    origin=${@: -2:1}
    "$REAL_GIT" init -q "$destination"
    "$REAL_GIT" -C "$destination" remote add origin "$origin"
else
    exec "$REAL_GIT" "$@"
fi
''')
    executable(bins / 'ssh-keygen', '''if [[ $1 == -t ]]; then
    exec "$REAL_KEYGEN" "$@" -N '' -q
else
    exec "$REAL_KEYGEN" "$@"
fi
''')
    environment = dict(os.environ, PREFIX=str(prefix), REAL_GIT=REAL_GIT,
                       REAL_KEYGEN=REAL_KEYGEN, PATH=str(bins) + ':' + os.environ['PATH'])
    for name in ('XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME'):
        environment.pop(name, None)

    def home(name):
        location = root / name
        location.mkdir()
        return location, dict(environment, HOME=str(location))

    def install(env, success=True):
        return run(['bash', str(checkout / 'install.sh')], env, success)

    fresh, env = home('fresh')
    install(env)
    key = (fresh / '.ssh/id_ed25519').read_bytes()
    config = fresh / '.ssh/config'
    config.write_text('Host personal\n    HostName example.invalid\n')
    manifest = fresh / '.config/yazi/package.toml'
    assert not manifest.is_symlink()
    manifest.write_text(manifest.read_text() + '\n# local change\n')
    install(env)
    assert (fresh / '.ssh/id_ed25519').read_bytes() == key
    assert 'personal' in config.read_text()
    assert '# local change' in manifest.read_text()
    assert (fresh / '.zshrc').is_symlink()
    assert (fresh / '.termux/heliboard/main.jsonc').exists()
    assert (fresh / '.termux/colors.properties').is_symlink()
    assert (fresh / '.termux/font.ttf').read_bytes().startswith(b'\x00\x01\x00\x00')
    assert not (fresh / '.termux/font.ttf').is_symlink()
    assert not (checkout / 'zsh/.local').exists()
    print('PASS: fresh bootstrap and safe rerun, paths containing spaces')

    font = fresh / '.termux/font.ttf'
    font_updater = ['bash', str(fresh / '.local/bin/termux-update-font')]
    original_font = font.read_bytes()
    calls = (fresh / 'calls').read_text()
    run(font_updater, env)
    assert (fresh / 'calls').read_text() == calls
    for mode in ('failed', 'invalid'):
        run(font_updater, dict(env, FONT_DOWNLOAD_MODE=mode), success=False)
        assert font.read_bytes() == original_font
        assert not list((fresh / '.termux').glob('.font.*'))
    previous_font = fresh / 'previous.ttf'
    previous_font.write_bytes(b'previous custom font')
    font.unlink()
    font.symlink_to(previous_font)
    run(font_updater, env)
    assert not font.is_symlink()
    assert font.read_bytes() == original_font
    assert previous_font.read_bytes() == b'previous custom font'
    backup = fresh / '.termux/font.ttf.bak'
    assert backup.read_bytes() == previous_font.read_bytes()
    font.write_bytes(b'another version')
    run(font_updater, env)
    assert backup.read_bytes() == previous_font.read_bytes()
    assert (fresh / 'calls').read_text().count('termux-reload-settings') == calls.count('termux-reload-settings') + 2
    print('PASS: font no-op, failed/invalid downloads, atomic replacement, backup and symlink safety')

    conflict, conflict_env = home('conflict')
    (conflict / '.zshrc').write_text('keep me\n')
    install(conflict_env, success=False)
    assert (conflict / '.zshrc').read_text() == 'keep me\n'
    assert not (conflict / '.config/nvim/init.lua').exists()
    assert not (conflict / '.ssh').exists()
    print('PASS: Stow conflicts fail before deploying any package')

    existing, existing_env = home('existing key')
    (existing / '.ssh').mkdir()
    private = existing / '.ssh/custom-name'
    run([REAL_KEYGEN, '-t', 'ed25519', '-N', '', '-q', '-f', str(private)], existing_env)
    expected_public = private.with_suffix('.pub').read_text().split()[:2]
    private.with_suffix('.pub').unlink()
    original = private.read_bytes()
    result = install(existing_env)
    assert ' '.join(expected_public) in result.stdout
    assert private.read_bytes() == original
    assert not (existing / '.ssh/id_ed25519').exists()
    print('PASS: custom private key without public file is preserved and displayed')

    blocked, blocked_env = home('blocked key')
    (blocked / '.ssh').mkdir()
    (blocked / '.ssh/id_ed25519').symlink_to(blocked / 'missing')
    install(blocked_env, success=False)
    assert (blocked / '.ssh/id_ed25519').is_symlink()
    print('PASS: dangling key symlinks are never replaced')

    config.write_text('''Host first second * !excluded foo? bar[12]
    HostName never-offer-this
hOsT = third first # ignore-comment
Host "quoted"
Match host no-match
''')
    hosts = run(['zsh', '-fc', 'source "$HOME/.config/zsh/ssh-hosts.zsh"; termux_ssh_hosts'], env)
    assert hosts.stdout.splitlines() == ['first', 'quoted', 'second', 'third'], hosts.stdout
    print('PASS: host aliases are deduplicated; patterns, HostName and Match excluded')
