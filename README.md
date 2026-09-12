# piper-pi

Repeatable headless setup for a Raspberry Pi 4 running Raspberry Pi OS Lite
64-bit. The card boots on Ethernet, enables SSH, joins Tailscale, installs the
managed configuration, and checks this repository for updates.

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
  --github-key ~/.ssh/id_ed25519 \
  --tailscale-auth-key-file /path/to/tailscale-auth-key
```

The command requires `sudo`, checks that the device is removable and at least
8 GiB, verifies the image checksum, writes the image, and unmounts it before
returning. It does not back up the selected device; check the printed device
identity before accepting the destructive write.

Put the card in the Pi and connect Ethernet before applying power. First boot
usually takes several minutes while packages and Tailscale are installed.

```sh
ssh pi
pi-status
sudo pi-update
```

The prepared `piper` account has the supplied GitHub key and can clone and push
all repositories that key can access. The website repository is cloned during
first boot to `~/repos/piper-wolf.github.io`. The first boot performs no website
commit or push.

## Updates

The Pi checks `main` every five minutes and applies changed configuration. A
daily systemd timer updates packages. Updates are serialized and never reboot
automatically.

```sh
sudo pi-update             # configuration from origin/main
sudo pi-update --os        # configuration plus apt update/full-upgrade
pi-status
```

For recovery, apply a known commit and return to tracking `main` later:

```sh
sudo pi-update --pin <commit>
sudo pi-update --follow-main
```

Major Raspberry Pi OS releases should be installed by preparing a new card.
