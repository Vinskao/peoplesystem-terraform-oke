#!/usr/bin/env bash
set -euo pipefail

DUMP_DIR="${DUMP_DIR:-/dump}"
FILE=$(find "$DUMP_DIR" -maxdepth 1 -type f -name '*.sql.gz' -print -quit)
test -n "$FILE"
test -s "$FILE"
gzip -t "$FILE"
NAME=$(basename "$FILE")

echo "Uploading verified backup $NAME to oci://$OCI_BUCKET"
oci os object put --auth instance_principal \
  --namespace "$OCI_NAMESPACE" --bucket-name "$OCI_BUCKET" \
  --name "$NAME" --file "$FILE" --force
echo "Backup uploaded: $NAME"
