# PWA-Innomotics

Next.js 15 + HeroUI v3, behind **App Service Easy Auth**. Container port 3000 (`next dev` uses 3011).

## Pingpong session rules
Easy Auth does all of it. The only app-side piece is `middleware.ts`, which stamps when a new Easy Auth cookie is first seen (`pwa_session_started`, display only) for the countdown:

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

## Release / deploy
Run the scripts from **Git Bash** (Windows), WSL, macOS or Linux - not PowerShell/cmd.

**First time:** install [Docker Desktop](https://www.docker.com/products/docker-desktop/) (running) and the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), then `az login --tenant 8c66b612-f806-4e98-8ffb-dacca0235e16`. `./scripts/release.sh --check` tells you if anything is missing.

**Release (normal case):** commit your changes, `git pull`, then
```bash
./scripts/release.sh
```
It builds + pushes `pwaqa.azurecr.io/pwa-innomotics:build-<utc>-<commit>` (and `:latest`), shows what `PWAQA` runs now vs. after, asks before deploying, restarts, and waits until `/api/health` returns 200. Takes ~5-10 min.

| Script | What it does |
|---|---|
| `release.sh [--yes] [--allow-dirty] [--port N] [--startup "<cmd>"]` | push + deploy + health check |
| `push-image.sh [tag] [--allow-dirty] [--verbose]` | build + push only |
| `deploy-webapp.sh --tag <tag> [--port 3000] [--startup "<cmd>"] [--image <repo>] [--yes]` | point `PWAQA` at an existing image, restart, health check. Prints the roll-back command before changing anything |
| `list-images.sh [--name <acr>] [--repo <repo>] [--top 10]` | tags in a registry, newest first |

Every script: `--help`, `--check` (checks only, changes nothing), numbered stages `[n/N] ... DONE (12s)` / `FAILED`, colored `[ok]`/`[warn]`/`[FAIL]`, and the fix command for each failure. `NO_COLOR=1` turns colors off.

Rules the scripts enforce: uncommitted changes block a release (the image must match a commit; `--allow-dirty` to override); deploys use exact tags, `:latest` only with a warning. Defaults (`pwaqa`, `PWAQA`, rg `PWA-QA`, image `pwa-innomotics`) live in `scripts/lib.sh` and can be overridden with env vars.

**Roll back:** `./scripts/list-images.sh --repo pwa-innomotics`, then `./scripts/deploy-webapp.sh --tag <older tag>`.

The web app pulls with its system-assigned identity, which needs `AcrPull` on the registry.