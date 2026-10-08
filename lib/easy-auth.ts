import { headers } from "next/headers";

import { SESSION_HEADER, SESSION_MINUTES } from "@/lib/session";

export type EasyAuthUser = { name: string; email: string; sessionExpiresAt: number | null;
  now: number;
  issuedAt: number | null;
  principal: unknown;
  idToken: { header: unknown; payload: unknown } | null;
};

// Decode only (no signature check): Easy Auth already validated it, and this is
// purely for display.
function decodeJwt(jwt: string | null) {
  const [h, p] = jwt?.split(".") ?? [];

  if (!h || !p) return null;

  try {
    const part = (v: string) => JSON.parse(Buffer.from(v, "base64url").toString("utf8"));

    return { header: part(h), payload: part(p) };
  } catch {
    return null;
  }
}

type Claim = { typ: string; val: string };

const claim = (claims: Claim[], ...types: string[]) =>
  claims.find((c) => types.includes(c.typ))?.val ?? "";

// App Service Easy Auth injects X-MS-CLIENT-PRINCIPAL (base64 JSON) on every
// authenticated request; nothing client-side (no MSAL) is needed.
export async function getUser(): Promise<EasyAuthUser | null> {
  const h = await headers();
  const raw = h.get("x-ms-client-principal");

  if (!raw) return null;

  try {
    const principal = JSON.parse(Buffer.from(raw, "base64").toString("utf8"));
    const claims: Claim[] = principal.claims ?? [];
    const email =
      h.get("x-ms-client-principal-name") ||
      claim(claims, "preferred_username", "upn", "email");

    // Login moment stamped by middleware.ts when this Easy Auth login was first seen.
    const startedAt = Number(h.get(SESSION_HEADER)) || 0;
    const sessionExpiresAt = startedAt ? startedAt + SESSION_MINUTES * 60_000 : null;
    const issuedAt = Number(claim(claims, "iat", "auth_time")) || null;

    // Only present when the App Service token store is enabled.
    const idToken = decodeJwt(h.get("x-ms-token-aad-id-token"));

    return { name: claim(claims, "name") || email, email, sessionExpiresAt, now: Date.now(), issuedAt, principal, idToken };
  } catch {
    return null;
  }
}
