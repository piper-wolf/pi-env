#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

repo=/opt/pi-env
state=/var/lib/pi-env
log=/var/log/pi-env-bootstrap.log
mkdir -p "$state"
exec >>"$log" 2>&1
printf '%s bootstrap started\n' "$(date --iso-8601=seconds)"

if [[ -e "$state/bootstrap-complete" ]]; then
  printf '%s bootstrap already complete\n' "$(date --iso-8601=seconds)"
  exit 0
fi

# The key is injected before first boot, before cloud-init creates piper.
# Normalize ownership here so image UID allocation cannot affect SSH access.
install -d -m 0700 -o piper -g piper /home/piper/.ssh
chown piper:piper /home/piper/.ssh/id_ed25519 /home/piper/.ssh/id_ed25519.pub /home/piper/.ssh/known_hosts
chmod 0600 /home/piper/.ssh/id_ed25519
chmod 0644 /home/piper/.ssh/id_ed25519.pub /home/piper/.ssh/known_hosts

install -d -m 0755 /etc/ssh/ssh_config.d
cat >/etc/ssh/ssh_config.d/99-pi-env-github.conf <<'EOF'
Host github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking yes
EOF
chmod 0644 /etc/ssh/ssh_config.d/99-pi-env-github.conf

for attempt in $(seq 1 30); do
  if curl --fail --silent --show-error --max-time 10 https://tailscale.com >/dev/null; then break; fi
  printf 'waiting for network (%s/30)\n' "$attempt"
  sleep 10
done

if ! command -v tailscale >/dev/null 2>&1; then
  curl --fail --silent --show-error https://tailscale.com/install.sh | sh
fi

if [[ -s /root/pi-env.tailscale-auth-key && ! -s /var/lib/tailscale/tailscaled.state ]]; then
  tailscale up --ssh --auth-key="file:/root/pi-env.tailscale-auth-key" --hostname=piper-pi
  shred --remove /root/pi-env.tailscale-auth-key
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install --yes ansible-core
fi

ansible-playbook --connection=local --inventory=localhost, "$repo/ansible/site.yml"
touch "$state/bootstrap-complete"
printf '%s bootstrap complete\n' "$(date --iso-8601=seconds)"
