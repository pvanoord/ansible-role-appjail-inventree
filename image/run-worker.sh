#!/bin/sh
set -eu

cd /inventree/src/src/backend/InvenTree
exec python3.11 manage.py qcluster
