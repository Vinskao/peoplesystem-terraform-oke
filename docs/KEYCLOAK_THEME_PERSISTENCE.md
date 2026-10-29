# Keycloak login theme persistence

## Goal

The TY Multiverse Keycloak login and registration screens should share the site's black, charcoal, white, and gray design. Preserve Keycloak's own login/registration behavior, localization, and validation by extending the maintained `keycloak.v2` theme and adding CSS only.

## Durable configuration model

Keycloak has two separate pieces of state:

1. **Theme files** (`theme.properties`, CSS, images) must be delivered from a Kubernetes ConfigMap or a versioned Keycloak image. Files copied into a running container are ephemeral and disappear when that Pod is replaced.
2. **Realm's Login theme selection** is Realm configuration stored in the Keycloak database. With the current PostgreSQL backend, a Pod restart should retain this setting as long as the PostgreSQL database and its persistent volume are retained.

Do not treat either an in-container edit or a manually selected theme as fully handed off unless its source and activation procedure are documented here and represented declaratively in the repository.

The same Keycloak SSO is only for TY Multiverse's own approval interface. It is not a Threads or LinkedIn sign-in and does not grant permission to publish. Social publishing requires the separate provider OAuth grants documented in `../../ty-multiverse-frontend/docs/THREADS_LINKEDIN_AUTOMATION.md`.

## Current source and state (2026-10-29)

- Theme source: `../keycloak-theme/ty-multiverse/login/`.
- Keycloak image observed: `quay.io/keycloak/keycloak:26.1.4`; context path `/sso`.
- The Deployment currently has no theme volume. It is a single-replica `Recreate` Deployment, so any template change/restart temporarily interrupts SSO.
- The live Realm theme has **not** been changed. Admin CLI login attempts timed out. No ConfigMap, mount, or production rollout was applied in that session.
- A Kustomize ConfigMap generator and Deployment volume patch are saved in `../keycloak-theme/k8s/`. They have **not** been applied to the cluster.
- Therefore the theme is saved in the workspace repository, but it is **not yet active or persisted in the cluster**.
- The current live Deployment's administrator env is defined as literal values in its manifest. Before a future rollout, migrate the administrator credential to a Kubernetes Secret and rotate it; do not print or commit the secret value.

## Apply checklist

1. Migrate/rotate the administrator credential into a Kubernetes Secret; do not expose its value.
2. Render the checked-in ConfigMap with `kubectl kustomize keycloak-theme/` and review the output. The Deployment mount is a separate strategic patch.
3. Verify the active Realm and its existing `loginTheme` value with an authenticated admin session. Preserve the old value for rollback.
4. Set the Realm's Login theme to `ty-multiverse` through the Keycloak Admin Console or `kcadm.sh`; this setting must be persisted in the Realm database, not only in a container file.
5. Once the theme files, admin Secret, Realm setting, and rollback value are ready, apply `kubectl apply -k keycloak-theme/`, then `kubectl patch deployment keycloak -n default --type=strategic --patch-file keycloak-theme/k8s/deployment-theme-volume-patch.yaml`. Wait for rollout and confirm `/sso` login and registration pages render, including mobile and error states.
6. Verify a Pod replacement/restart retains the selected theme. Confirm PostgreSQL persistence separately; do not infer database durability from Pod readiness.

## Rollback

Restore the recorded prior Realm `loginTheme`, remove the ConfigMap mount (or revert the image), and roll the Deployment. Because the Deployment uses `Recreate`, coordinate this as a brief SSO interruption and verify recovery afterward.

## Operational rules

- Never print Keycloak passwords, tokens, Kubernetes Secret values, or admin config into terminal output or commit them.
- Do not restart production until the theme package, Realm setting, and rollback value are all ready.
- Keep the live Kubernetes manifest and its source of truth synchronized. If the Deployment is manually managed, add the declarative artifact to this repo before changing it.
- Validate the Realm setting after a restart; theme files alone do not select the theme.
