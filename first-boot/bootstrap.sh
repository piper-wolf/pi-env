#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

repo=/opt/pi-env
state=/var/lib/pi-env
log=/var/log/pi-env-bootstrap.log
mkdir -p "$state"
exec >>"$log" 2>&1
printf '%s bootstrap started\n' "$(date --iso-8601=seconds)"

# Keep a small, secret-free status report on the root filesystem and on the
# boot partition. The latter remains readable from another computer if SSH,
# Tailscale, or cloud-init fails before the system is reachable.
boot_status=''
for boot_dir in /boot/firmware /boot; do
  if [[ -d "$boot_dir" ]] && mountpoint -q "$boot_dir" 2>/dev/null; then
    boot_status="$boot_dir/pi-env-status"
    break
  fi
done

write_status() {
  local phase=$1
  local detail=${2:-}
  local now tmp
  now=$(date --iso-8601=seconds)
  tmp=$(mktemp "$state/status.XXXXXX") || return 0
  {
    printf 'updated=%s\n' "$now"
    printf 'phase=%s\n' "$phase"
    printf 'hostname=%s\n' "$(hostname 2>/dev/null || printf unknown)"
    printf 'addresses=%s\n' "$(hostname -I 2>/dev/null | xargs || printf unknown)"
    if [[ -n "$detail" ]]; then
      printf 'detail=%s\n' "$detail"
    fi
  } >"$tmp"
  chmod 0644 "$tmp"
  mv -f -- "$tmp" "$state/status"
  if [[ -n "$boot_status" ]]; then
    tmp="$boot_status.tmp"
    cp -- "$state/status" "$tmp" 2>/dev/null || true
    mv -f -- "$tmp" "$boot_status" 2>/dev/null || true
  fi
}

on_error() {
  local rc=$?
  write_status failed "exit=$rc line=${BASH_LINENO[0]:-unknown}"
  printf '%s bootstrap failed (exit %s)\n' "$(date --iso-8601=seconds)" "$rc"
  exit "$rc"
}
trap on_error ERR

if [[ -e "$state/bootstrap-complete" ]]; then
  write_status complete already-complete
  printf '%s bootstrap already complete\n' "$(date --iso-8601=seconds)"
  exit 0
fi

write_status starting

# The key is injected before first boot, before cloud-init creates piper.
# Normalize ownership here so image UID allocation cannot affect GitHub access.
install -d -m 0700 -o piper -g piper /home/piper/.ssh
chown piper:piper /home/piper/.ssh/piper-pi-github /home/piper/.ssh/known_hosts
chmod 0600 /home/piper/.ssh/piper-pi-github
chmod 0644 /home/piper/.ssh/known_hosts

install -d -m 0755 /etc/ssh/ssh_config.d
cat >/etc/ssh/ssh_config.d/99-pi-env-github.conf <<'EOF'
Host github.com
  User git
  IdentityFile ~/.ssh/piper-pi-github
  IdentitiesOnly yes
  StrictHostKeyChecking yes
EOF
chmod 0644 /etc/ssh/ssh_config.d/99-pi-env-github.conf

network_ready=0
for attempt in $(seq 1 30); do
  write_status waiting-for-network "attempt=$attempt/30"
  if curl --fail --silent --show-error --max-time 10 https://tailscale.com >/dev/null; then
    network_ready=1
    break
  fi
  printf 'waiting for network (%s/30)\n' "$attempt"
  sleep 10
done

if (( ! network_ready )); then
  write_status failed network-unavailable
  exit 1
fi

if ! command -v tailscale >/dev/null 2>&1; then
  write_status installing-tailscale
  curl --fail --silent --show-error https://tailscale.com/install.sh | sh
fi

if [[ -s /root/pi-env.tailscale-auth-key && ! -s /var/lib/tailscale/tailscaled.state ]]; then
  write_status authenticating-tailscale
  tailscale up --ssh --auth-key="file:/root/pi-env.tailscale-auth-key" --hostname=piper-pi
  shred --remove /root/pi-env.tailscale-auth-key
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  write_status installing-ansible
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install --yes ansible-core
fi

write_status configuring
ansible-playbook --connection=local --inventory=localhost, "$repo/ansible/site.yml"
touch "$state/bootstrap-complete"
write_status complete
printf '%s bootstrap complete\n' "$(date --iso-8601=seconds)"
