#!/bin/sh
set -eu

cd /inventree/src/src/backend/InvenTree
exec python3.12 manage.py qcluster
