# Object Storage Terraform Root

This directory is an independent Terraform root for OCI Object Storage buckets.

It is intentionally separate from the main OKE Terraform root so bucket changes do not share state with the cluster, network, or worker resources.

## What it creates

- One `oci_objectstorage_bucket`

## Why this is safer

- Separate Terraform state from the OKE deployment
- `prevent_destroy = true` to reduce accidental bucket deletion
- Default `access_type = "NoPublicAccess"`

## Usage

1. Copy `terraform.tfvars.example` to `terraform.tfvars`
2. Set a unique `bucket_name`
3. Run:

```bash
terraform init
terraform plan
terraform apply
```

## Notes

- The bucket still counts toward your tenancy's Object Storage quota and Always Free usage.
- `Standard` and `Archive` share the free storage pool you mentioned.
- Keep this directory's `.tfstate` separate from the main root's state.
