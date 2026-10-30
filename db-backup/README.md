# DB Backup Terraform Root

Independent Terraform root that provisions the **infrastructure** for backing up the self-hosted
in-cluster PostgreSQL to OCI Object Storage. The backup **job itself** runs as a Kubernetes
CronJob (`k8s-cronjob.yaml`).

## What it creates

- `oci_objectstorage_bucket` `peoplesystem-db-backup` (private, versioning enabled)
- Object lifecycle policy: archive after 7 days, delete after 30 days (auto-rotation)
- Dynamic group + policy so OKE worker nodes can **write** objects to this bucket via Instance
  Principal — no stored keys

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars   # set compartment_id
terraform init
terraform plan
terraform apply

# deploy both the application DB and Keycloak DB backups
kubectl apply -k .
# run each backup once immediately to verify
kubectl create job -n default --from=cronjob/db-backup db-backup-manual
kubectl create job -n default --from=cronjob/keycloak-db-backup keycloak-db-backup-manual
kubectl logs -n default job/keycloak-db-backup-manual --all-containers -f
```

## Notes

- IAM (dynamic group + policy) must be applied against the tenancy **home region**.
- The CronJob uploads with `oci os object put --auth instance_principal`; the policy here scopes it
  to `manage objects` on this single bucket only.
- If the `ghcr.io/oracle/oci-cli` image can't be pulled in your cluster, swap it for any image that
  has the OCI CLI, or build a small one — the upload command is standard.
- Restore a dump:
  `gunzip -c peoplesystem-<ts>.sql.gz | psql -h postgres -U postgres -d peoplesystem`
- Keycloak connects to the `postgres` database. Its daily dump is named
  `keycloak-postgres-<UTC timestamp>.sql.gz` in the same private, versioned OCI bucket.
- Both scripts use `pipefail`, reject empty or invalid gzip files, and verify the archive before
  upload. A failed `pg_dump` prevents the upload container from running.
- The Admin Console's **Partial export** does not include users. The PostgreSQL logical dump is the
  recovery copy for Keycloak users, realms, clients, roles, and stored configuration.
