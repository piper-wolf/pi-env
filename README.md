# piper-pi

Repeatable headless setup for a Raspberry Pi 4 running Raspberry Pi OS Lite
64-bit. The card boots on Ethernet, enables SSH, joins Tailscale, installs the
chezmoi-managed configuration, then stops. This repository owns only image
preparation and initial bootstrapping; it has no recurring update timer.

The image itself is intentionally not committed. `bin/prepare-card` downloads
and verifies the pinned Raspberry Pi OS image, writes it to an explicitly
selected removable device, and injects the local credentials needed on first
boot.

## Prepare a card

Create a one-use, pre-approved Tailscale auth key in the Tailscale admin
console. Keep it in a root-readable file outside this repository. Then run:

```sh
cd ~/repos/pi-env
bin/prepare-card \
  --device /dev/disk/by-id/usb-Mass_Storage_Device_121220160204-0:0 \
  --tailscale-auth-key-file /path/to/tailscale-auth-key
```

The command creates a dedicated, passphrase-free Pi GitHub key at
`~/Downloads/piper-pi-github` (and its `.pub` file), injects only the private
key into the Pi, and records the public key and fingerprint under
`~/.config/pi-env/`. Add the `.pub` file to the GitHub account that owns the
repositories; GitHub never needs the private key. The local computer's existing
`~/.ssh/id_ed25519.pub` is used only to authorize SSH login to the Pi.

The command requires `sudo`, checks that the device is removable and at least
8 GiB, verifies the image checksum, writes the image, and unmounts it before
returning. It does not back up the selected device; check the printed device
identity before accepting the destructive write.

Put the card in the Pi and connect Ethernet before applying power. First boot
usually takes several minutes while packages and Tailscale are installed.

The bootstrap writes a secret-free status report to both
`/var/lib/pi-env/status` and the boot partition as `pi-env-status`. If the Pi
does not become reachable, power it down, remove the card, mount its boot
partition on this computer, and read that file before reimaging. It identifies
the last completed phase (for example `waiting-for-network`,
`authenticating-tailscale`, or `configuring`) without exposing credentials.

```sh
ssh pi
pi-status
sudo pi-update
```

The prepared `piper` account has the supplied GitHub key and can clone and push
all repositories that key can access. The website repository is cloned during
first boot to `~/repos/piper-wolf.github.io`. The first boot performs no website
commit or push.

## Add another SSH login key

Normal OpenSSH login is public-key-only by default. To enroll a key from a new
computer, use the existing login to enable password authentication for `piper`
and set a strong password:

```sh
ssh -t pi-lan sudo pi-ssh-password-auth enable
```

On the new computer, send its public key with the password. `ssh-copy-id` adds
the key to `/home/piper/.ssh/authorized_keys` only after the password login
succeeds:

```sh
ssh-copy-id -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no -i ~/.ssh/id_ed25519.pub \
  piper@piper-pi.local
```

Verify key-only login from the new computer, then turn password authentication
off again:

```sh
ssh -o PreferredAuthentications=publickey \
  -o PasswordAuthentication=no piper@piper-pi.local
ssh -t pi-lan sudo pi-ssh-password-auth disable
```

This enrollment path is for the Pi's normal OpenSSH daemon. `ssh pi` uses
Tailscale SSH and its tailnet identity policy; it does not use the Pi password.

## Configuration and updates

Ongoing configuration belongs to [`piper-wolf/dotfiles`](https://github.com/piper-wolf/dotfiles),
using the `claw/linux/apt/server` profile. First boot installs chezmoi and runs
`ORGANIZATION=claw DEVICE=server chezmoi init --ssh --apply piper-wolf/dotfiles`.
The dedicated GitHub key and authorized login keys remain local and unmanaged.
The temporary system SSH client rule lets bootstrap clone dotfiles; chezmoi
then installs the user SSH config and retires that rule.

Dotfiles owns Git/SSH client configuration, packages, timezone, repository
clones, status/enrollment/control commands, and the publisher systemd units.
`dotfiles-update.timer` applies clean, fast-forward dotfiles changes every twenty
minutes; `server-os-update.timer` updates OS packages daily without rebooting.
`pi-update` remains a compatibility command installed by dotfiles:

```sh
chezmoi diff
chezmoi update
sudo pi-update             # chezmoi update as piper
sudo pi-update --os        # plus apt update/full-upgrade
pi-status
```

Commit local dotfiles source edits before updating. For recovery, use Git in the
chezmoi source checkout and `chezmoi apply`; the old `pi-update --pin` interface
is retired. Updating this image-builder repository never reapplies live configuration.
Major Raspberry Pi OS releases should be installed by preparing a new card.

## Daily pigeon publishing

Dotfiles installs the dependencies and clones `~/repos/pigeon-queue` and
`~/repos/piper-wolf.github.io` only if absent. The enabled publisher timer runs at
10am America/Los_Angeles with persistent missed-run recovery and twenty-minute
failure retries. The refresh timer updates queue code/dependencies every twenty
minutes without posting. Publication refreshes the queue and website using their
own locks; it no longer invokes pi-env or Ansible.

Credentials stay in `/home/piper/.config/pigeon-queue` (0700), with the Bluesky
app password in `bluesky-app-password` (0600). They are not managed by either
repository. `sudo pigeon-queue-service status|down|recreate` controls scheduling;
`down` persists in `/var/lib/pigeon-queue/disabled`. Migration preserves a prior
`/var/lib/pi-env/pigeon-queue.disabled` marker and retires the old update timers.
A missed daily run may publish when scheduling is recreated. Logs are available
with `journalctl -u pigeon-queue.service`.

Push routine queue/site changes to their `main` branches; their launchers pull
without requiring an SSH deployment. Push service/configuration changes to
`dotfiles/main`, then apply with chezmoi or let its timer update. For publisher
recovery and exact-post retries, follow the queue README and raspberry-pi-ops skill.

## Checks

Run `python3 tests/bootstrap.py` before pushing bootstrap changes. It checks shell
syntax, fresh chezmoi installation, the initial profile handoff, and repeated boot
in an isolated mock filesystem; it never flashes a card or touches live services.
