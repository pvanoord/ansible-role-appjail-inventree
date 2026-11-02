#!/bin/sh
set -eu

cd /inventree/src/src/backend/InvenTree
exec gunicorn \
    --bind 0.0.0.0:8000 \
    --workers "${INVENTREE_GUNICORN_WORKERS:-3}" \
    --timeout "${INVENTREE_GUNICORN_TIMEOUT:-120}" \
    --pid /inventree/run/pid \
    --worker-tmp-dir /inventree/run \
    --access-logfile - \
    --error-logfile - \
    InvenTree.wsgi
