#!/usr/bin/env bash
set -euo pipefail

: "${PGDATABASE:?PGDATABASE is required}"
: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"

DUMP_DIR="${DUMP_DIR:-/dump}"
BACKUP_NAME="${BACKUP_NAME:-$PGDATABASE}"
TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT="${DUMP_DIR}/${BACKUP_NAME}-${TS}.sql.gz"
trap 'status=$?; if [ "$status" -ne 0 ]; then rm -f "$OUT"; fi; exit "$status"' EXIT

echo "Dumping ${PGDATABASE} from ${PGHOST}:${PGPORT} -> ${OUT}"
pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" --no-owner --no-privileges \
  | gzip -c > "$OUT"
test -s "$OUT"
gzip -t "$OUT"
ls -lh "$OUT"
