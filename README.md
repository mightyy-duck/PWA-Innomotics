# PWA-Innomotics

Next.js 15 + HeroUI v3, behind **App Service Easy Auth**. Port 3011.

## Pingpong session rules
Pingpong forces a login on every access, so the app destroys the Easy Auth session itself:

| Trigger | What happens |
|---|---|
| New visit (no `pwa_sid`), or tab/browser reopened | middleware -> `/.auth/logout` -> `/signed-out` (public page, user presses Log in) -> `/relogin` -> `/.auth/login/aad?prompt=select_account` -> `/auth/established` stamps `pwa_sid` -> `/` |
| Session older than `SESSION_TTL_MINUTES` (15) | same, enforced by middleware on navigation and by `SessionGuard` timer in an open tab |
| Switch account button | same |
| Password changed on the primary account | **Not handled here** - needs an IdP-side signal (e.g. Entra revoke / CAE); the 15 min TTL is the upper bound |

Logout always returns to our own `/signed-out`, never Microsoft's "signed out" page (the stuck-on-logout symptom).

## Easy Auth config (required)
- Identity provider issuer: `https://login.microsoftonline.com/<TENANT 2 (product) ID>/v2.0` - NOT `/common` or tenant 1.
- Require authentication; unauthenticated -> HTTP 302 to Microsoft login.
- Excluded paths (no login needed): `/signed-out`, `/relogin`, `/api/health`, `/_next/*` (assets for the signed-out page). Portal: Authentication > Edit > *Restrict access: Require authentication*, then set `globalValidation.excludedPaths` via `az rest` on `.../config/authsettingsV2`. `/signed-out` must never redirect to login itself.
- Allowed external redirect not needed; all redirects are relative.
- If the picker/forced login does not appear, add `prompt` to the provider's `loginParameters` - the app already sends `?prompt=select_account` and Easy Auth may not forward it (use `["prompt=select_account"]`).
- Easy Auth token store cookie lifetime should be <= the TTL.

## Settings
`SESSION_TTL_MINUTES` (default 15). Container listens on 3011 - set `WEBSITES_PORT=3011`.

## Deploy
`ACR_NAME=<qa-registry> QA_TENANT_ID=<guid> ./scripts/push-image.sh`
