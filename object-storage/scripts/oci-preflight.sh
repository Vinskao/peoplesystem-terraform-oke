#!/usr/bin/env bash
# Research Zone mapping bucket preflight.
#
# Run this ON AN OKE WORKER NODE so it uses the same instance principal as the pods:
#   scp scripts/oci-preflight.sh oke-node:/tmp/ && ssh oke-node 'bash /tmp/oci-preflight.sh'
#
# Verifies, in order:
#   1. GET the production mapping object
#   2. PUT a preflight object
#   3. GET it back and compare sha256
#   4. Confirm DELETE is refused (the workload principal must not be able to delete)
# Preflight objects are removed by the bucket lifecycle rule, not by this script.

set -uo pipefail

NS="${OCI_OS_NAMESPACE:-axbptfyngj39}"
BUCKET="${OCI_OS_BUCKET:-peoplesystem-object-storage-20260618}"
REGION="${OCI_OS_REGION:-ap-singapore-2}"
OBJECT="${OCI_OS_OBJECT:-company-product-mapping.json}"
PREFIX="${OCI_OS_PREFLIGHT_PREFIX:-_preflight/}"

OCI=(oci os --auth instance_principal --region "$REGION")
PROBE="${PREFIX}probe-$(date -u +%Y%m%dT%H%M%SZ)-$$.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
step() { printf '\n=== %s\n' "$1"; }
ok()   { printf 'OK   %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fail=1; }

step "1. GET production object ${OBJECT}"
if "${OCI[@]}" object get -ns "$NS" -bn "$BUCKET" --name "$OBJECT" --file "$TMP/current.json" >/dev/null 2>"$TMP/err"; then
  bytes=$(wc -c <"$TMP/current.json")
  ok "read ${bytes} bytes"
  python3 -c "import json,sys; d=json.load(open('$TMP/current.json')); print('   rackParts:', len(d.get('rackParts', [])), '| updatedAt:', d.get('updatedAt'))" || bad "not valid mapping JSON"
else
  bad "$(head -3 "$TMP/err")"
fi

step "2. PUT preflight object ${PROBE}"
echo "{\"preflight\":true,\"at\":\"$(date -u +%FT%TZ)\"}" >"$TMP/probe.json"
expected=$(sha256sum "$TMP/probe.json" | cut -d' ' -f1)
if "${OCI[@]}" object put -ns "$NS" -bn "$BUCKET" --name "$PROBE" --file "$TMP/probe.json" --force >/dev/null 2>"$TMP/err"; then
  ok "wrote preflight object"
else
  bad "$(head -3 "$TMP/err")"
fi

step "3. GET back and verify sha256"
if "${OCI[@]}" object get -ns "$NS" -bn "$BUCKET" --name "$PROBE" --file "$TMP/probe-readback.json" >/dev/null 2>"$TMP/err"; then
  actual=$(sha256sum "$TMP/probe-readback.json" | cut -d' ' -f1)
  if [ "$expected" = "$actual" ]; then ok "hash matches ${actual:0:16}..."; else bad "hash mismatch"; fi
else
  bad "$(head -3 "$TMP/err")"
fi

step "4. DELETE must be refused"
if "${OCI[@]}" object delete -ns "$NS" -bn "$BUCKET" --name "$PROBE" --force >/dev/null 2>"$TMP/err"; then
  bad "delete succeeded — the workload principal has more permission than intended"
else
  ok "delete refused as expected ($(grep -o '"code": "[^"]*"' "$TMP/err" | head -1))"
fi

printf '\n=== preflight %s (preflight objects expire via the bucket lifecycle rule)\n' \
  "$([ "$fail" -eq 0 ] && echo PASSED || echo FAILED)"
exit "$fail"
