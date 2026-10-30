# Keycloak login theme persistence

## Goal

The TY Multiverse Keycloak login and registration screens should share the site's black, charcoal, white, and gray design. Preserve Keycloak's own login/registration behavior, localization, and validation by extending the maintained `keycloak.v2` theme and adding CSS only.

## Durable configuration model

Keycloak has two separate pieces of state:

1. **Theme files** (`theme.properties`, CSS, images) must be delivered from a Kubernetes ConfigMap or a versioned Keycloak image. Files copied into a running container are ephemeral and disappear when that Pod is replaced.
2. **Realm's Login theme selection** is Realm configuration stored in the Keycloak database. With the current PostgreSQL backend, a Pod restart should retain this setting as long as the PostgreSQL database and its persistent volume are retained.

Do not treat either an in-container edit or a manually selected theme as fully handed off unless its source and activation procedure are documented here and represented declaratively in the repository.

The same Keycloak SSO is only for TY Multiverse's own approval interface. It is not a Threads or LinkedIn sign-in and does not grant permission to publish. Social publishing requires the separate provider OAuth grants documented in `../../ty-multiverse-frontend/docs/THREADS_LINKEDIN_AUTOMATION.md`.

## Current source and state (2026-10-30)

- Theme source: `../keycloak-theme/ty-multiverse/login/`.
- Keycloak image observed: `quay.io/keycloak/keycloak:26.1.4`; context path `/sso`.
- The Deployment now mounts the `keycloak-login-theme` ConfigMap. It is a single-replica `Recreate` Deployment, so any template change/restart temporarily interrupts SSO.
- The live PeopleSystem Realm login theme is still the default (the Themes selector showed `Choose...`). Selecting `ty-multiverse` is pending an authenticated admin session; retain the default as the rollback value.
- Realm internationalization is enabled; the default locale is `zh-TW`, with `zh-TW` and `en` supported. This setting was saved in the Admin Console and Keycloak confirmed the Realm update.
- The Kustomize ConfigMap and Deployment volume patch have been applied; the custom theme files survive Pod replacement. The realm has not yet selected the theme, so the login screen still uses the default appearance.
- After the rollout, `wavo` successfully signed into the master account console. The admin console repeatedly displayed “Something went wrong” while loading, even after retrying; the master OpenID discovery and PeopleSystem login endpoint returned HTTP 200. Ingress logs show the hidden third-party-cookie check `step1.html` returned 200 without a subsequent `step2.html` request for the embedded check; opening `step1.html` directly did reach step2. The user confirmed Chrome already allowed third-party cookies and added a site exception, but the admin console still failed. The precise browser or script failure remains unconfirmed. A single official `kcadm` read-only attempt using the existing `keycloak-admin` Secret returned `invalid_grant`; do not retry those credentials repeatedly or assume they match the user-managed `wavo` password. Investigate the admin console before selecting the theme; do not update the realm database directly or assume that Pod readiness proves the console is usable.
- The live Deployment contains legacy bootstrap administrator environment settings, while a `keycloak-admin` Secret also exists. These are not the current `wavo` account password: the stored account is in the existing master realm database. Keycloak's bootstrap credentials create an initial admin only before the master realm exists; changing them does not reset an existing account. Do not copy the user-managed `wavo` password into Kubernetes or print/commit any credential. Review and remove or secure unused bootstrap values as a separate hardening task.
- PostgreSQL uses the `shared-pvc-1` claim with the `postgres` database for Keycloak. Its restart and backup verification are recorded in [`KEYCLOAK_PERSISTENCE_AND_USER_INVENTORY.md`](KEYCLOAK_PERSISTENCE_AND_USER_INVENTORY.md).

## Apply checklist

1. Verify the existing `wavo` admin login through the browser. Do not rotate its password by changing bootstrap environment variables; those only apply before the master realm exists.
2. Render the checked-in ConfigMap with `kubectl kustomize keycloak-theme/` and review the output. The Deployment mount is a separate strategic patch.
3. Verify the active Realm and its existing `loginTheme` value with an authenticated admin session. Preserve the old value for rollback.
4. Set the Realm's Login theme to `ty-multiverse` through the Keycloak Admin Console or `kcadm.sh`; this setting must be persisted in the Realm database, not only in a container file.
   - In **Realm settings → Localization**, enable internationalization, set **Default locale** to `zh-TW`, keep `en` in **Supported locales**, and leave the login locale selector available. This controls message translation; CSS only controls appearance.
5. Once the theme files, admin Secret, Realm setting, and rollback value are ready, apply `kubectl apply -k keycloak-theme/`, then `kubectl patch deployment keycloak -n default --type=strategic --patch-file keycloak-theme/k8s/deployment-theme-volume-patch.yaml`. Wait for rollout and confirm `/sso` login and registration pages render, including mobile and error states.
6. Verify a Pod replacement/restart retains the selected theme. Confirm PostgreSQL persistence separately; do not infer database durability from Pod readiness.

## Rollback

Restore the recorded prior Realm `loginTheme`, remove the ConfigMap mount (or revert the image), and roll the Deployment. Because the Deployment uses `Recreate`, coordinate this as a brief SSO interruption and verify recovery afterward.

## Operational rules

- Never print Keycloak passwords, tokens, Kubernetes Secret values, or admin config into terminal output or commit them.
- Do not restart production until the theme package, Realm setting, and rollback value are all ready.
- Keep the live Kubernetes manifest and its source of truth synchronized. If the Deployment is manually managed, add the declarative artifact to this repo before changing it.
- Validate the Realm setting after a restart; theme files alone do not select the theme.
