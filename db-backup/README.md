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

# then deploy the backup job
kubectl apply -f k8s-cronjob.yaml
# run it once immediately to verify
kubectl create job -n default --from=cronjob/db-backup db-backup-manual
kubectl logs -n default job/db-backup-manual --all-containers -f
```

## Notes

- IAM (dynamic group + policy) must be applied against the tenancy **home region**.
- The CronJob uploads with `oci os object put --auth instance_principal`; the policy here scopes it
  to `manage objects` on this single bucket only.
- If the `ghcr.io/oracle/oci-cli` image can't be pulled in your cluster, swap it for any image that
  has the OCI CLI, or build a small one — the upload command is standard.
- Restore a dump:
  `gunzip -c peoplesystem-<ts>.sql.gz | psql -h postgres -U postgres -d peoplesystem`
