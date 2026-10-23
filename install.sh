#!/usr/bin/env bash
#
# Installs (or updates) Watchtower Controller from this repository.
#
# Usage, as root, from the repository folder:
#   ./install.sh            install / update files, timer left as it is
#   ./install.sh --enable   also enable and start the daily timer
#
# Existing configuration (etc/controller.env, etc/hosts.conf) is never
# overwritten: on a first install the examples are copied in their place.

set -euo pipefail

BASE_DIR="/opt/watchtower-controller"
UNIT_DIR="/etc/systemd/system"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENABLE_TIMER=false

case "${1:-}" in
    "") ;;
    --enable) ENABLE_TIMER=true ;;
    *) echo "Usage: $0 [--enable]" >&2; exit 1 ;;
esac

if [[ ${EUID} -ne 0 ]]; then
    echo "Run as root." >&2
    exit 1
fi

for cmd in docker flock timeout systemctl; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "Missing requirement: ${cmd}" >&2
        exit 1
    fi
done

echo "==> Installing into ${BASE_DIR}"

install -d -m 750 "${BASE_DIR}" "${BASE_DIR}/bin" "${BASE_DIR}/etc"
install -d -m 700 "${BASE_DIR}/logs" "${BASE_DIR}/state" "${BASE_DIR}/certs"

install -m 750 "${SRC_DIR}/bin/watchtower-controller" "${BASE_DIR}/bin/watchtower-controller"

install_config() {
    local name="$1"
    local mode="$2"

    if [[ -e "${BASE_DIR}/etc/${name}" ]]; then
        echo "    keeping existing etc/${name}"
    else
        install -m "${mode}" "${SRC_DIR}/etc/${name}.example" "${BASE_DIR}/etc/${name}"
        echo "    created etc/${name} from the example: edit it"
    fi
}

install_config controller.env 600
install_config hosts.conf 640

install -m 644 "${SRC_DIR}/systemd/watchtower-controller.service" "${UNIT_DIR}/"
install -m 644 "${SRC_DIR}/systemd/watchtower-controller.timer" "${UNIT_DIR}/"
systemctl daemon-reload

if [[ "${ENABLE_TIMER}" == "true" ]]; then
    systemctl enable --now watchtower-controller.timer
    systemctl list-timers watchtower-controller.timer --no-pager
fi

cat <<EOF

Done. Next steps:
  1. Edit ${BASE_DIR}/etc/hosts.conf and ${BASE_DIR}/etc/controller.env
  2. For TLS hosts, put ca.pem, cert.pem, key.pem in ${BASE_DIR}/certs/<host>/
  3. Test one host:   ${BASE_DIR}/bin/watchtower-controller <host>
  4. Enable the timer: systemctl enable --now watchtower-controller.timer
EOF
