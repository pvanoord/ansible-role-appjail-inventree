#!/bin/sh
set -eu

APP_BACKEND=/inventree/src/src/backend
APP_CONFIG="${APP_BACKEND}/InvenTree/config.yaml"
APP_MARKER=/.inventree-done/skip-initialization
export INVENTREE_CONFIG_FILE="${APP_CONFIG}"
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/inventree/.local/bin"

mkdir -p /inventree/log /inventree/run /inventree/data/static /inventree/data/media
chown inventree:inventree /inventree/log /inventree/run
cp /usr/local/etc/inventree/config.yaml "${APP_CONFIG}"
chown inventree:inventree "${APP_CONFIG}"

for script in \
    basic admin secret-key database email currency cors file-storage-locations \
    background login sentry customisation plugin cache extras
do
    /bin/sh "/scripts/${script}.sh" >/dev/null
done
chmod 0600 "${APP_CONFIG}"

if [ ! -f "${APP_MARKER}" ]; then
    su -m inventree -c 'cd /inventree/src && invoke update'

    if [ "${INVENTREE_PLATFORM_UI:-1}" = "1" ]; then
        inventree_version="$(su -m inventree -c \
            'cd /inventree/src && invoke version | grep -Ee "^InvenTree   " | cut -d" " -f4')"
        test -n "${inventree_version}"
        su -m inventree -c \
            "cd /inventree/src && invoke frontend-download -t '${inventree_version}'"
        mkdir -p /inventree/data/static/web
        cp -R /inventree/src/src/backend/InvenTree/web/static/web/. \
            /inventree/data/static/web/
        chown -R inventree:inventree /inventree/data/static
    fi

    touch "${APP_MARKER}"
fi

su -m inventree -c /usr/local/bin/inventree-run-web &
web_pid=$!
su -m inventree -c /usr/local/bin/inventree-run-worker &
worker_pid=$!
shutdown() {
    trap - INT TERM
    kill "${web_pid}" "${worker_pid}" 2>/dev/null || true
    wait || true
    exit 0
}
trap shutdown INT TERM

while kill -0 "${web_pid}" 2>/dev/null && kill -0 "${worker_pid}" 2>/dev/null; do
    sleep 2
done

set +e
wait "${web_pid}"
status=$?
kill "${worker_pid}" 2>/dev/null
wait "${worker_pid}"
worker_status=$?
set -e

if [ "${status}" -eq 0 ]; then
    status="${worker_status}"
fi
if [ "${status}" -eq 0 ]; then
    status=1
fi
exit "${status}"
