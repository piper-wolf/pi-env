"""Verify first boot hands off once to chezmoi, without recurring provisioning."""
import os
import re
from pathlib import Path
import subprocess
import tempfile
source = Path(__file__).resolve().parents[1]
subprocess.run(['bash', '-n', str(source / 'first-boot/bootstrap.sh'), str(source / 'bin/prepare-card')], check=True)
assert 'ansible-playbook' not in (source / 'first-boot/bootstrap.sh').read_text()
assert not (source / 'ansible').exists() and not (source / 'systemd').exists()
with tempfile.TemporaryDirectory(prefix='pi-bootstrap-') as directory:
    root = Path(directory)
    mock = root / 'mock'; mock.mkdir()
    def executable(path, body):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('#!/bin/bash\nset -e\n' + body); path.chmod(0o755)
    for name in ['chown', 'chmod']:
        executable(mock / name, 'exit 0\n')
    executable(mock / 'install', '''args=()
while (($#)); do
  case "$1" in -o|-g) shift 2;; *) args+=("$1"); shift;; esac
done
exec /usr/bin/install "${args[@]}"
''')
    executable(mock / 'curl', 'exit 0\n')
    executable(mock / 'tailscale', 'echo 100.64.0.1\n')
    executable(mock / 'sudo', 'while [[ ${1:-} == -* ]]; do if [[ $1 == -u ]]; then shift 2; else shift; fi; done\nexec "$@"\n')
    calls = root / 'calls'
    executable(root / 'home/piper/.local/bin/chezmoi', 'printf "%s %s %s\\n" "$ORGANIZATION" "$DEVICE" "$*" >> "$CALLS"\n')
    (root / 'var/log').mkdir(parents=True)
    script = (source / 'first-boot/bootstrap.sh').read_text()
    for path in ['/home/piper', '/var/lib', '/var/log', '/etc', '/root', '/boot', '/opt']:
        script = re.sub(re.escape(path) + r'(?=[/"\s;]|$)', str(root) + path, script)
    env = dict(os.environ, PATH=f'{mock}:/usr/bin:/bin', CALLS=str(calls))
    for _ in range(2):
        result = subprocess.run(['bash'], input=script, text=True, env=env)
        assert result.returncode == 0, (root / 'var/log/pi-env-bootstrap.log').read_text()
    assert calls.read_text().splitlines() == ['claw server init --ssh --apply piper-wolf/dotfiles']
    assert (root / 'var/lib/pi-env/bootstrap-complete').exists()
    assert 'phase=complete' in (root / 'var/lib/pi-env/status').read_text()
    # Exercise a fresh card without chezmoi as well as the retry path above.
    (root / 'var/lib/pi-env/bootstrap-complete').unlink()
    (root / 'home/piper/.local/bin/chezmoi').unlink()
    executable(mock / 'curl', """if [[ "$*" == *get.chezmoi.io* ]]; then
cat <<'INSTALLER'
#!/bin/bash
mkdir -p "$HOME/.local/bin"
install -m 0755 /dev/stdin "$HOME/.local/bin/chezmoi" <<'CHEZMOI'
#!/bin/bash
printf '%s %s %s\\n' "$ORGANIZATION" "$DEVICE" "$*" >> "$CALLS"
CHEZMOI
INSTALLER
fi
""")
    env['HOME'] = str(root / 'home/piper')
    for _ in range(2):
        result = subprocess.run(['bash'], input=script, text=True, env=env)
        assert result.returncode == 0, (root / 'var/log/pi-env-bootstrap.log').read_text()
    assert calls.read_text().splitlines() == ['claw server init --ssh --apply piper-wolf/dotfiles'] * 2
print('Bootstrap syntax, installation, one-time chezmoi handoff, and repeat boot passed.')
