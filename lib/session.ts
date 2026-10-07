import { createHmac, timingSafeEqual } from "node:crypto";

// The app, not Easy Auth, is the authority for "how long is this session".
// Easy Auth's cookie expiry is unreadable, so we stamp the login moment ourselves
// (/auth/established) and enforce the limit in middleware.ts.
export const SESSION_COOKIE = "pwa_session";
export const SESSION_MINUTES = Number(process.env.SESSION_MINUTES) || 15;
export const SESSION_HEADER = "x-session-started";

const secret = () => {
  const s = process.env.SESSION_SECRET;

  if (!s) throw new Error("SESSION_SECRET is not set");

  return s;
};

const mac = (start: number) => createHmac("sha256", secret()).update(String(start)).digest("hex");

export const signStart = (start: number) => `${start}.${mac(start)}`;

// Returns the login time (epoch ms) if the stamp is genuine and not yet expired.
export function verifyStamp(value: string | undefined, now = Date.now()): number | null {
  const [startStr, sig] = (value ?? "").split(".");
  const start = Number(startStr);

  if (!start || !sig) return null;

  const expected = Buffer.from(mac(start));
  const given = Buffer.from(sig);

  if (expected.length !== given.length || !timingSafeEqual(expected, given)) return null;

  return now < start + SESSION_MINUTES * 60_000 && start <= now + 5_000 ? start : null;
}

export const isHttps = (req: { nextUrl: { protocol: string }; headers: Headers }) =>
  req.nextUrl.protocol === "https:" || req.headers.get("x-forwarded-proto") === "https";
