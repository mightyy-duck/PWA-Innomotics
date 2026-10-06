# PWA-Innomotics

Next.js 15 + HeroUI v3, behind **App Service Easy Auth**. Container port 3000 (`next dev` uses 3011).

## Pingpong session rules
Easy Auth does all of it; the app has no middleware or session cookie of its own:

| Trigger | What happens |
|---|---|
| Any visit without an Easy Auth session | Easy Auth -> Microsoft login (forced, `prompt=login`) -> back to the page |
| Session older than 15 min | Easy Auth cookie expires (`cookieExpiration` FixedTime 00:15:00); next request logs in again |
| Log out button | `/signout` expires the `AppServiceAuthSession` cookie in the app -> `/.auth/login/aad?post_login_redirect_uri=/` -> login -> `/` |
| Password changed on the primary account | **Not handled here** - needs an IdP-side signal (e.g. Entra revoke / CAE); the 15 min cookie is the upper bound |

Log out never uses `/.auth/logout`: that goes through Microsoft's logout page ("Pick an account to sign out").

## Easy Auth config (required)
- Identity provider issuer: `https://login.microsoftonline.com/<TENANT 2 (product) ID>/v2.0` - NOT `/common` or tenant 1.
- Require authentication; unauthenticated -> HTTP 302 to Microsoft login.
- AAD `loginParameters`: `["prompt=login"]` - forces credentials on every login.
- Cookie expiration: FixedTime `00:15:00`.
- Excluded paths (no login needed): `/signout`, `/api/health`, `/_next/static/*`. Set `globalValidation.excludedPaths` via `az rest` on `.../config/authsettingsV2`.
- Allowed external redirect not needed; all redirects are relative.

## Deploy
`ACR_NAME=<qa-registry> QA_TENANT_ID=<guid> ./scripts/push-image.sh`
