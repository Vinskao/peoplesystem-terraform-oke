# TY Multiverse Keycloak login theme

This theme styles both Keycloak sign-in and account-registration forms with the site's black, charcoal, white, and gray palette. It extends the Keycloak 26 `keycloak.v2` login theme, so form behavior, accessibility structure, localization, and validation remain owned by Keycloak.

## Package and enable

Package `ty-multiverse/login` as a directory under `/opt/keycloak/themes/` (for example, mount it from a ConfigMap or bake it into the Keycloak image). Then select `ty-multiverse` as the realm's **Login theme** under **Realm settings → Themes**. Registration inherits the same login theme.

The current Keycloak Deployment has no theme volume and its realm theme selection has not been changed. Do not restart the production Deployment until the theme is mounted and an operator with valid realm-admin access has selected it. A restart temporarily interrupts `/sso`.

## Rollback

Set the realm's Login theme back to its previously recorded value (normally `keycloak.v2`), then remove the theme mount or image layer. Rebuild/restart Keycloak only if the theme source was baked into the image or its theme cache requires a restart.

## Files

- `ty-multiverse/login/theme.properties`: inherits Keycloak's maintained v2 login screens.
- `ty-multiverse/login/resources/css/login.css`: grayscale presentation only; no custom credential or registration logic.
