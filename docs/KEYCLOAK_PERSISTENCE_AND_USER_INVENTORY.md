# Keycloak persistence and account inventory

Last verified: 2026-10-30 (Asia/Taipei)

## Storage and restart behavior

| Component | Current configuration | Persistence / status |
|---|---|---|
| Keycloak | `quay.io/keycloak/keycloak:26.1.4`, one replica, context path `/sso` | Realm and user records are in PostgreSQL, not the Keycloak container filesystem. |
| Database | PostgreSQL service `postgres`, database `postgres` for Keycloak | PostgreSQL StatefulSet mounts `shared-pvc-1` at `/var/lib/postgresql/data` with subPath `postgres`. |
| Persistent volume | `shared-pvc-1`, 50 GiB, status `Bound`, OCI Block Volume | Replacing/restarting a Pod reuses the claim. Deleting the PVC or its volume can lose the live copy. |
| PostgreSQL resources | Request `25m` CPU / `384Mi`; limit `500m` CPU / `1Gi`; longer probes | Updated after the verified backup below to reduce probe-driven restarts while fitting the node's remaining schedulable CPU. |
| Bootstrap administrator | Deployment startup bootstrap variables are not the stored Keycloak account credential after the master realm exists | Do not reset `wavo` by editing startup variables. The account password is stored in Keycloak's database. |

Keycloak official documentation confirms that its relational database stores users, clients, and realms. A Pod restart alone does not remove those records when PostgreSQL and its volume remain available.

## User and administrator status recorded from the current account screen

This is a non-secret status record, not an export of every account. Full user records and realm configuration are covered by the PostgreSQL database backup described below.

| Username | Realm | Password | MFA | Notes |
|---|---|---|---|---|
| `wavo` | `master` (admin account) | User reported completing a password change on 2026-10-30; never store the password here | Account screen shows an enrolled authenticator credential; secret/seed not recorded | Current signed-in Keycloak account shown in the user's screenshot. |

Do not record passwords, password hashes, TOTP seeds, recovery codes, session tokens, or client secrets in this Markdown file or Git.

## What the Admin Console export covers

The **Realm settings → Action → Partial export** function exports realm configuration and selected resources such as clients, roles, and groups. It does **not** export realm users. Keycloak's official export guide documents this limitation. Therefore, the recoverable full copy must be a database backup, not only `realm-export.json` from the console.

## Backup design

- The existing `db-backup` job backs up the `peoplesystem` application database.
- Keycloak connects to the separate `postgres` database. The `keycloak-db-backup` CronJob backs up this database to the private, versioned OCI bucket `peoplesystem-db-backup` daily at 03:30 Asia/Taipei.
- The Keycloak dump filename is `keycloak-postgres-<UTC timestamp>.sql.gz`.
- Both dump and upload scripts validate a non-empty gzip archive. `pg_dump` pipeline failure removes the partial file and fails the init container, so the uploader cannot upload a truncated dump as a successful backup.
- PostgreSQL credentials are read from the Kubernetes Secret at runtime and are never written to the repo or printed by the backup scripts.

## Live database health note

At the time of the incident, PostgreSQL had 49 restarts and repeated readiness/liveness timeouts. An initial manual dump of the application database was interrupted by a PostgreSQL restart and was deleted before its upload container started; do not treat that run as a backup. The Keycloak database backup then completed successfully:

- Job: `keycloak-db-backup-verify-20261030`
- OCI object: `keycloak-postgres-20261030T045009Z.sql.gz`
- `pg_dump` completed; the gzip archive was checked; OCI Object Storage returned a successful upload response.
- The PVC remained Bound throughout; PostgreSQL performed WAL recovery after a restart.

The live PostgreSQL StatefulSet was updated to the resource/probe configuration in `../postgres/statefulset.yaml`. Because it uses `OnDelete`, `postgres-0` was explicitly replaced after the Keycloak database backup completed. The replacement mounted the existing `shared-pvc-1`, logged that the database directory already contained a database, completed startup recovery, and became Ready with zero restarts. The PVC remained Bound at 50 GiB, and the external SSO admin console returned HTTP 200 after recovery.

Before claiming full recovery protection, confirm a `keycloak-db-backup` Job completes and logs both a verified dump and a successful OCI upload. Restore testing is a separate step and should use an isolated database, never overwrite the production database as a test.
