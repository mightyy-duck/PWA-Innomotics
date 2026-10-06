// Pingpong requires a forced login on every access. Easy Auth alone keeps its
// own cookie alive, so this app layers its own short-lived marker on top:
//   pwa_sid      session cookie (dies with the browser) = issued-at epoch ms,
//                set only right after a fresh login (/auth/established).
//   pwa_relogin  one-shot flag proving the login was started by /relogin.
// No valid pwa_sid (new visit, expired, tampered) => destroy the Easy Auth
// session and log in again.
export const SID_COOKIE = "pwa_sid";
export const RELOGIN_COOKIE = "pwa_relogin";

export const ttlMs = () => {
  const m = Number(process.env.SESSION_TTL_MINUTES);
  return (Number.isFinite(m) && m > 0 ? m : 15) * 60_000;
};

export const isFresh = (sid: string | undefined, now = Date.now()) => {
  const issued = Number(sid);
  return Number.isFinite(issued) && issued <= now + 5_000 && now - issued < ttlMs();
};

// Where the browser goes after Easy Auth has cleared its session: our public
// /signed-out page (excluded from Easy Auth), where the user presses Log in.
export const relogin = () => "/signed-out";

// Full-page navigation; Easy Auth endpoints are not Next routes. Logging out
// returns to OUR /signed-out, never to Microsoft's dead-end "signed out" page.
export const logoutThen = (next: string) =>
  `/.auth/logout?post_logout_redirect_uri=${encodeURIComponent(next)}`;
