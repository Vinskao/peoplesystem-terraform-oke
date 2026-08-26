# Bucket rename: `peoplesystem-object-storage-20260618` → `peoplesystem-research-zone`

The old name carries a creation date, which reads like a one-off resource.

**The old bucket is NOT empty.** It holds the live `company-product-mapping.json`
(3,703 bytes, created 2026-06-18T04:45:35Z, ETag `ac5602bc-da26-4d15-9aa6-12520a0ec97e`),
verified byte-identical to the classpath fallback
(sha256 `56723299cd470d7ad4b7f1e9e924b120a08af31209f067f50b959b6dad1e08d9`).

So this is a **copy-then-cut-over**, not a rename-in-place:

1. Terraform forgets the old bucket (`state rm`) — it stays in OCI, untouched and unmanaged.
2. Terraform creates the new bucket.
3. The object is copied and verified by hash.
4. Only after preflight passes does the backend switch over.
5. The old bucket is kept as a rollback target and removed later, as a separate decision.

Terraform never gets the chance to destroy a bucket that holds data.

## 0. Prerequisites

```bash
oci session authenticate --profile peoplesystem-v2   # both sessions are currently expired
cd peoplesystem-terraform-oke/object-storage
```

## 1. Back up state

```bash
cp terraform.tfstate "terraform.tfstate.backup-$(date -u +%Y%m%dT%H%M%SZ)"
```

## 2. Home region (verified)

The tenancy home region is **ap-singapore-2** (key `XSP`) — the same region as the bucket, so no
cross-region provider is actually needed. `home_region` defaults to that value, and the
`oci_identity_dynamic_group` precondition fails the plan if it ever disagrees with the tenancy's
real home region, so a wrong value cannot slip through.

```bash
oci iam region-subscription list --profile peoplesystem-v2 --auth security_token \
  --query 'data[?"is-home-region"].{region:"region-name",key:"region-key"}' --output table
```

## 3. Download and verify the current production object

```bash
oci os object get --profile peoplesystem-v2 --auth security_token --region ap-singapore-2 \
  -ns axbptfyngj39 -bn peoplesystem-object-storage-20260618 \
  --name company-product-mapping.json --file /tmp/oci-live-object.json

shasum -a 256 /tmp/oci-live-object.json \
  ../../ty-multiverse-backend/src/main/resources/data/company-product-mapping.json
```

Both hashes must be `56723299cd470d7ad4b7f1e9e924b120a08af31209f067f50b959b6dad1e08d9`.
Keep this file — it is the source for step 7 and the rollback copy.

## 4. Drop the old bucket from Terraform state

```bash
terraform state rm oci_objectstorage_bucket.this
```

This only forgets the resource; the bucket and its object still exist in OCI, untouched.
From here on the old bucket is unmanaged, which also means Terraform can never destroy it.

## 5. Plan

```bash
terraform plan -out tfplan
```

The plan must contain exactly these creates and nothing else:

- `oci_objectstorage_bucket.this` — name `peoplesystem-research-zone`, `versioning = "Enabled"`
- `oci_objectstorage_object_lifecycle_policy.preflight_cleanup`
- `oci_identity_dynamic_group.object_storage_readers[0]`
- `oci_identity_policy.object_storage_access[0]`

If anything else appears (especially a destroy), stop.

## 6. Apply

```bash
terraform apply tfplan
terraform output tenancy_home_region bucket_versioning
```

## 7. Copy the production object into the new bucket and verify

```bash
oci os object put --profile peoplesystem-v2 --auth security_token --region ap-singapore-2 \
  -ns axbptfyngj39 -bn peoplesystem-research-zone \
  --name company-product-mapping.json \
  --file /tmp/oci-live-object.json \
  --content-type application/json

oci os object get --profile peoplesystem-v2 --auth security_token --region ap-singapore-2 \
  -ns axbptfyngj39 -bn peoplesystem-research-zone \
  --name company-product-mapping.json --file /tmp/oci-new-readback.json

shasum -a 256 /tmp/oci-new-readback.json   # must match 56723299cd47...
```

## 8. Preflight from a worker node (same instance principal as the pods)

```bash
scp scripts/oci-preflight.sh oke-node:/tmp/
ssh oke-node 'OCI_OS_BUCKET=peoplesystem-research-zone bash /tmp/oci-preflight.sh'
```

All four checks must pass, including step 4 (delete must be REFUSED).

## 9. Point the backend at the new bucket

```bash
ssh oke-node 'kubectl patch configmap ty-multiverse-backend-config \
  --type merge -p "{\"data\":{\"OCI_OS_BUCKET\":\"peoplesystem-research-zone\"}}"'
ssh oke-node 'kubectl rollout restart deploy/ty-multiverse-backend'
ssh oke-node 'kubectl rollout status deploy/ty-multiverse-backend --timeout=180s'
```

Then confirm the fallback warning is gone:

```bash
ssh oke-node 'kubectl logs deploy/ty-multiverse-backend --since=5m | grep -i "classpath fallback\|BucketNotFound" || echo "clean"'
```

## 10. Keep the old bucket (for now)

The old bucket stays as-is: it still holds the pre-cutover object and is the rollback target if
anything about the new bucket misbehaves. Removing it is a separate decision to make only after
the new bucket has been stable in production, and it is no longer managed by Terraform, so it
must be deleted by hand when that time comes:

```bash
# ONLY after the new bucket is confirmed stable — not part of this migration.
oci os object delete --profile peoplesystem-v2 --auth security_token --region ap-singapore-2 \
  -ns axbptfyngj39 -bn peoplesystem-object-storage-20260618 --object-name company-product-mapping.json --force
oci os bucket delete --profile peoplesystem-v2 --auth security_token --region ap-singapore-2 \
  -ns axbptfyngj39 -bn peoplesystem-object-storage-20260618 --force
```

---

## Known limitation: instance principal blast radius

The dynamic group matches worker-node *instances*, so in principle any pod scheduled on those
nodes can use the node identity. That is why every policy statement is scoped with
`target.bucket.name = 'peoplesystem-research-zone'` — a pod that borrows the node identity still
cannot touch any other bucket, and cannot delete anything in this one.

The long-term fix is OKE workload identity (`resource.type = 'workload'` matching rules bound to a
specific namespace + service account), which narrows the principal from "any pod on the node" to
"this service account". Deferred deliberately; revisit before granting any further permissions.
