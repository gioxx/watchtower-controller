# Watchtower Controller

One [Watchtower](https://github.com/nicholas-fedor/watchtower) for all the Docker hosts in your homelab.

Instead of running a Watchtower container on every host, a single "controller" machine runs a throwaway Watchtower (`--run-once`) against each host's Docker API, one host after the other, on a systemd timer. One configuration, one schedule, one place for logs and notifications. Nothing to install on the managed hosts.

```text
controller host (Docker + systemd timer)
 ├─ watchtower --run-once ──unix socket──▶ itself
 ├─ watchtower --run-once ──tcp:2376 mTLS──▶ docker02
 └─ watchtower --run-once ──tcp:2376 mTLS──▶ nas
```

It uses the maintained fork `nickfedor/watchtower` (the original `containrrr/watchtower` is archived). All the usual `WATCHTOWER_*` options work.

## Features

- Local socket, remote Docker API with **mutual TLS**, or plain TCP (trusted LAN only)
- Per-host enable/disable switch
- Connectivity check with timeout: an offline host is skipped, it doesn't stall the run
- Lock file: a manual run never overlaps the scheduled one
- Watchtower image refreshed at every run, with fallback to the cached image
- One log per run, `latest.log`, `errors.log` with the controller's own errors, 30-day retention
- One JSON state file per host (`success`, `failed`, `unreachable`, `invalid_endpoint`), handy for dashboards or monitoring
- Non-zero exit code if any host fails, so systemd marks the unit as failed
- Run a single host: `watchtower-controller <host>`

## Requirements

On the controller host: Docker, systemd, `bash`, `flock`, `timeout` (all present on any Debian/Ubuntu).
On the managed hosts: nothing, as long as their Docker API is reachable from the controller.

## Install

```bash
git clone https://github.com/gioxx/watchtower-controller.git
cd watchtower-controller
sudo ./install.sh
```

No git on the controller? Download the archive of the [latest release](https://github.com/gioxx/watchtower-controller/releases/latest), extract it and run `sudo ./install.sh` from that folder.

`sudo ./install.sh --enable` also enables and starts the daily timer. Without it the timer is installed but left off, so you can configure and test first (see [Schedule](#schedule)).

Files end up in `/opt/watchtower-controller`:

```text
/opt/watchtower-controller/
├── bin/watchtower-controller
├── etc/
│   ├── controller.env   # Watchtower options, same for every host (chmod 600)
│   └── hosts.conf       # hosts to update
├── certs/<host>/        # client certificates for TLS hosts
├── logs/                # one log per run + errors.log + latest.log
└── state/               # <host>.json, outcome of the last run
```

Running `install.sh` again updates the script and the systemd units, and never touches your configuration. To update:

```bash
cd watchtower-controller
git pull
sudo ./install.sh
```

## Configure

### `etc/hosts.conf`

One host per line: `name|docker_host|enabled[|tls_dir]`

```text
docker-main|unix:///var/run/docker.sock|true
docker02|tcp://docker02.example.com:2376|true|/opt/watchtower-controller/certs/docker02
nas|tcp://nas.example.com:2376|false|/opt/watchtower-controller/certs/nas
```

The name ends up in the container name, the state file and the notification title (`WATCHTOWER_NOTIFICATION_TITLE_TAG`), so you know which host a message is about.

### `etc/controller.env`

Passed as-is to every Watchtower container. See the [Watchtower documentation](https://watchtower.nickfedor.com/) for all options; notifications use [Shoutrrr](https://containrrr.dev/shoutrrr/) URLs (Telegram, Discord, ntfy, Gotify, e-mail…).

Containers you don't want updated: add the label `com.centurylinklabs.watchtower.enable=false`. Set `WATCHTOWER_MONITOR_ONLY=true` for a first, harmless run that only reports what would be updated.

## Remote hosts: use TLS

A Docker API on `tcp://…:2375` has **no encryption and no authentication**: whoever reaches that port is root on the host. Don't use it outside a LAN you fully trust, and never expose it to the internet.

The right way is port 2376 with mutual TLS: the daemon only accepts clients presenting a certificate signed by your CA. Docker's guide: [Protect the Docker daemon socket](https://docs.docker.com/engine/security/protect-access/). For each TLS host, copy the client `ca.pem`, `cert.pem` and `key.pem` to `/opt/watchtower-controller/certs/<host>/` and set that directory as the fourth field in `hosts.conf`. The controller checks the files, uses them for its own connectivity check and mounts them read-only into Watchtower (`DOCKER_TLS_VERIFY=1`, `/etc/ssl/docker`).

## Schedule

The timer runs every day at 07:00 (`Persistent=true`: if the machine was off, it runs at boot). Change `OnCalendar` with `systemctl edit watchtower-controller.timer`.

```bash
sudo systemctl enable --now watchtower-controller.timer   # enable
systemctl list-timers watchtower-controller.timer         # next run
sudo /opt/watchtower-controller/bin/watchtower-controller docker02   # one host, now
journalctl -fu watchtower-controller                       # follow a run
tail -f /opt/watchtower-controller/logs/latest.log
```

## Don't mix updaters

If a host is managed by an orchestrator that updates images on its own (Komodo, Portainer, Dockge auto-update…), leave it out of `hosts.conf` or disable that feature. Two updaters on the same containers race each other, and updating an orchestrator's own containers (e.g. its core) without its agents can leave it with mismatched versions.

## License

[MIT](LICENSE)
