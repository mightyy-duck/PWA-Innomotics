import { headers } from "next/headers";

export type EasyAuthUser = { name: string; email: string; sessionExpiresAt: number | null;
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

// Must match Easy Auth cookieExpiration (FixedTime). The AppServiceAuthSession
// cookie is HttpOnly + encrypted and its expiry never reaches the server or JS,
// so we derive it: login time (id token iat) + this many minutes.
const SESSION_MINUTES = Number(process.env.EASY_AUTH_SESSION_MINUTES) || 15;

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

    const loggedInAt = Number(claim(claims, "iat", "auth_time"));
    const sessionExpiresAt = loggedInAt ? (loggedInAt + SESSION_MINUTES * 60) * 1000 : null;

    // Only present when the App Service token store is enabled.
    const idToken = decodeJwt(h.get("x-ms-token-aad-id-token"));

    return { name: claim(claims, "name") || email, email, sessionExpiresAt, principal, idToken };
  } catch {
    return null;
  }
}
