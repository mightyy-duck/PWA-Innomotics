import { createHash, createHmac, timingSafeEqual } from "node:crypto";

// Easy Auth's cookie (FixedTime cookieExpiration) is what ends a session. Its
// expiry is unreadable, so for the countdown we stamp when each Easy Auth login is
// first seen (middleware.ts). The stamp is bound to that login's cookie: a new
// login gets a new stamp automatically, so the app never has to force a re-login
// (which is what caused double logins and loops).
export const SESSION_COOKIE = "pwa_session";
export const SESSION_MINUTES = Number(process.env.SESSION_MINUTES) || 15;
export const SESSION_HEADER = "x-session-started";

const secret = () => {
  const s = process.env.SESSION_SECRET;

  if (!s) throw new Error("SESSION_SECRET is not set");

  return s;
};

const mac = (data: string) => createHmac("sha256", secret()).update(data).digest("hex");

// Identifies the current Easy Auth login: hash of its (possibly chunked) cookie(s).
export const easyAuthSessionId = (cookies: { name: string; value: string }[]) => {
  const parts = cookies
    .filter((c) => c.name.startsWith("AppServiceAuthSession"))
    .sort((a, b) => a.name.localeCompare(b.name))
    .map((c) => c.value);

  return parts.length ? createHash("sha256").update(parts.join("|")).digest("hex").slice(0, 32) : null;
};

export const signStamp = (start: number, sid: string) => `${start}.${sid}.${mac(`${start}.${sid}`)}`;

// Returns the login time (epoch ms) if the stamp is genuine and belongs to this
// Easy Auth login; otherwise null (caller stamps the login as starting now).
export function verifyStamp(value: string | undefined, sid: string): number | null {
  const [startStr, stampSid, sig] = (value ?? "").split(".");
  const start = Number(startStr);

  if (!start || !stampSid || !sig || stampSid !== sid) return null;

  const expected = Buffer.from(mac(`${start}.${stampSid}`));
  const given = Buffer.from(sig);

  if (expected.length !== given.length || !timingSafeEqual(expected, given)) return null;

  return start;
}

export const isHttps = (req: { nextUrl: { protocol: string }; headers: Headers }) =>
  req.nextUrl.protocol === "https:" || req.headers.get("x-forwarded-proto") === "https";
